import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'world_node_shadow_migration.dart';

class AppDatabase {
  AppDatabase._(this.database);
  factory AppDatabase.fromOpenDatabase(Database database) =>
      AppDatabase._(database);
  final Database database;
  static const schemaVersion = 19;

  static Future<AppDatabase> inMemory() => _open(inMemoryDatabasePath);
  static Future<AppDatabase> open(String path) => _open(path);
  static Future<AppDatabase> _open(String path) async {
    sqfliteFfiInit();
    return openWithFactory(path, databaseFactoryFfi);
  }

  static Future<AppDatabase> openWithFactory(
    String path,
    DatabaseFactory factory,
  ) async {
    final database = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (database) => database.execute('PRAGMA foreign_keys = ON'),
        onCreate: _createSchema,
        onUpgrade: _upgradeSchema,
      ),
    );
    return AppDatabase._(database);
  }

  static Future<void> _createSchema(Database database, int version) async {
    await database.execute('''CREATE TABLE categories (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL UNIQUE CHECK(length(trim(name)) > 0),
      sort_order INTEGER NOT NULL,
      color_key INTEGER NOT NULL CHECK(color_key BETWEEN 0 AND 7),
      created_at_utc INTEGER NOT NULL,
      updated_at_utc INTEGER NOT NULL
    )''');
    await WorldNodeShadowMigration.createWorldNodeTable(database);
    await _createPlanningTables(database);
    await _createFlatEventTable(database, 'events');
    await _createRunSegments(database);
    await _createRoutineCategoryTables(database);
    await _createRoutineTables(database);
    await _createEventDayPlans(database);
    await _createJaxDayCarryOverInitializations(database);
    await _createWorldCategoryCollapsePreferences(database);
    await _createSyncMetadata(database);
    await _createDatasetMetadata(database);
    await _createSyncTriggers(database);
  }

  static Future<void> _upgradeSchema(
    Database database,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) await _createLegacyRunSegments(database);
    if (oldVersion < 3) {
      await database.execute(
        'ALTER TABLE events ADD COLUMN parent_event_id TEXT REFERENCES events(id) ON DELETE RESTRICT',
      );
    }
    if (oldVersion < 4) {
      await database.execute(
        'ALTER TABLE events ADD COLUMN sort_order INTEGER',
      );
      await database.execute('''UPDATE events
        SET sort_order = (
          SELECT COUNT(*) - 1 FROM events sibling
          WHERE sibling.parent_event_id IS events.parent_event_id
            AND (sibling.created_at_utc < events.created_at_utc
              OR (sibling.created_at_utc = events.created_at_utc
                AND sibling.id <= events.id))
        )''');
    }
    if (oldVersion < 5) await _migrateToWaitingStatus(database);
    if (oldVersion < 6) {
      await database.execute('''CREATE TABLE categories (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL UNIQUE CHECK(length(trim(name)) > 0),
        sort_order INTEGER NOT NULL,
        created_at_utc INTEGER NOT NULL,
        updated_at_utc INTEGER NOT NULL
      )''');
      await database.execute(
        'ALTER TABLE events ADD COLUMN category_id TEXT REFERENCES categories(id) ON DELETE SET NULL',
      );
    }
    if (oldVersion < 7) await _createRoutineTables(database);
    if (oldVersion < 8) await _createEventDayPlans(database);
    if (oldVersion < 9) await _createWorldCategoryCollapsePreferences(database);
    if (oldVersion < 10) await _migrateToRoutineCategories(database);
    if (oldVersion < 11) await _migrateToCategoryColors(database);
    if (oldVersion < 12) await _migrateToOnDemandRoutines(database);
    if (oldVersion < 13) await _migrateToSyncMetadata(database);
    if (oldVersion < 14) {
      await WorldNodeShadowMigration.backfill(database);
      await _createSyncTriggers(database);
    }
    if (oldVersion < 15) {
      await _createPlanningTables(database);
      await _createSyncTriggers(database);
    }
    if (oldVersion < 16) await _migrateToFlatEvents(database);
    if (oldVersion < 17) {
      await _createPlanReviewNotes(database);
      await _createSyncTriggers(database);
    }
    if (oldVersion < 18) await _migratePlanningAttention(database);
    if (oldVersion < 19) {
      await _createJaxDayCarryOverInitializations(database);
    }
  }

  static Future<void> _createFlatEventTable(
    DatabaseExecutor database,
    String table,
  ) => database.execute('''CREATE TABLE $table (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL CHECK(length(trim(name)) > 0),
      status TEXT NOT NULL CHECK(status IN ('pending','running','paused','waiting','completed')),
      source_plan_item_id TEXT UNIQUE REFERENCES plan_items(id) ON DELETE RESTRICT,
      category_id TEXT REFERENCES categories(id) ON DELETE SET NULL,
      first_started_at_utc INTEGER,
      completed_at_utc INTEGER,
      created_at_utc INTEGER NOT NULL,
      updated_at_utc INTEGER NOT NULL,
      CHECK(source_plan_item_id IS NULL OR category_id IS NULL)
    )''');

  static Future<void> _migrateToFlatEvents(Database database) async {
    if (!await _tableExists(database, 'events')) {
      await _createDatasetMetadata(database);
      return;
    }
    if (!await _tableExists(database, 'categories')) {
      await database.execute('''CREATE TABLE categories (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL UNIQUE CHECK(length(trim(name)) > 0),
        sort_order INTEGER NOT NULL,
        color_key INTEGER NOT NULL CHECK(color_key BETWEEN 0 AND 7),
        created_at_utc INTEGER NOT NULL,
        updated_at_utc INTEGER NOT NULL
      )''');
    }
    await database.execute('PRAGMA defer_foreign_keys = ON');
    await _createFlatEventTable(database, 'events_v16');
    await database.execute('''WITH RECURSIVE roots(
        id, parent_event_id, root_category_id
      ) AS (
        SELECT id, parent_event_id, category_id FROM events
        WHERE parent_event_id IS NULL
        UNION ALL
        SELECT child.id, child.parent_event_id, roots.root_category_id
        FROM events child JOIN roots ON child.parent_event_id = roots.id
      )
      INSERT INTO events_v16(
        id, name, status, source_plan_item_id, category_id,
        first_started_at_utc, completed_at_utc, created_at_utc, updated_at_utc
      )
      SELECT event.id, event.name, event.status, NULL,
        COALESCE(roots.root_category_id, event.category_id),
        event.first_started_at_utc, event.completed_at_utc,
        event.created_at_utc, event.updated_at_utc
      FROM events event LEFT JOIN roots ON roots.id = event.id''');
    final hasSegments = await _tableExists(database, 'run_segments');
    if (hasSegments) {
      await database.execute('''CREATE TABLE run_segments_v16 (
      id TEXT PRIMARY KEY,
      event_id TEXT NOT NULL REFERENCES events_v16(id) ON DELETE CASCADE,
      started_at_utc INTEGER NOT NULL,
      ended_at_utc INTEGER,
      created_at_utc INTEGER NOT NULL,
      updated_at_utc INTEGER NOT NULL DEFAULT 0
    )''');
      await database.execute(
        'INSERT INTO run_segments_v16 SELECT * FROM run_segments',
      );
    }
    final hasDayPlans = await _tableExists(database, 'event_day_plans');
    if (hasDayPlans) {
      await database.execute('''CREATE TABLE event_day_plans_v16 (
      event_id TEXT NOT NULL REFERENCES events_v16(id) ON DELETE CASCADE,
      day_date TEXT NOT NULL,
      order_index INTEGER NOT NULL,
      created_at_utc INTEGER NOT NULL,
      updated_at_utc INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY(event_id, day_date)
    )''');
      await database.execute(
        'INSERT INTO event_day_plans_v16 SELECT * FROM event_day_plans',
      );
    }
    if (await _tableExists(database, 'legacy_event_world_node_links')) {
      await database.execute('DROP TABLE legacy_event_world_node_links');
    }
    if (await _tableExists(database, 'sync_tombstones')) {
      await database.delete(
        'sync_tombstones',
        where: 'entity_type = ?',
        whereArgs: ['legacyEventWorldNodeLink'],
      );
    }
    if (hasSegments) await database.execute('DROP TABLE run_segments');
    if (hasDayPlans) await database.execute('DROP TABLE event_day_plans');
    await database.execute('DROP TABLE events');
    await database.execute('ALTER TABLE events_v16 RENAME TO events');
    if (hasSegments) {
      await database.execute(
        'ALTER TABLE run_segments_v16 RENAME TO run_segments',
      );
    }
    if (hasDayPlans) {
      await database.execute(
        'ALTER TABLE event_day_plans_v16 RENAME TO event_day_plans',
      );
    }
    await _createDatasetMetadata(database);
    await _createSyncTriggers(database);
  }

  static Future<void> _createDatasetMetadata(Database database) async {
    await database.execute('''CREATE TABLE IF NOT EXISTS dataset_metadata (
        singleton INTEGER PRIMARY KEY CHECK(singleton = 1),
        generation TEXT NOT NULL CHECK(length(trim(generation)) > 0),
        created_at_utc INTEGER NOT NULL
      )''');
    await database.execute('''INSERT OR IGNORE INTO dataset_metadata(
        singleton, generation, created_at_utc)
      VALUES(1, lower(hex(randomblob(16))),
        CAST((julianday('now') - 2440587.5) * 86400000 AS INTEGER))''');
  }

  static Future<void> _createPlanningTables(Database database) async {
    await database.execute('''CREATE TABLE IF NOT EXISTS plans (
      id TEXT PRIMARY KEY,
      world_node_id TEXT NOT NULL REFERENCES world_nodes(id) ON DELETE RESTRICT,
      title TEXT,
      status TEXT NOT NULL CHECK(status IN ('current','ended')),
      round_number INTEGER NOT NULL CHECK(round_number > 0),
      ended_at_utc INTEGER,
      created_at_utc INTEGER NOT NULL,
      updated_at_utc INTEGER NOT NULL,
      UNIQUE(world_node_id, round_number),
      CHECK((status = 'ended' AND ended_at_utc IS NOT NULL) OR
            (status = 'current' AND ended_at_utc IS NULL))
    )''');
    await database.execute('''CREATE UNIQUE INDEX IF NOT EXISTS
      plans_one_current_per_world_node
      ON plans(world_node_id) WHERE status = 'current' ''');
    await database.execute('''CREATE TABLE IF NOT EXISTS plan_items (
      id TEXT PRIMARY KEY,
      plan_id TEXT NOT NULL REFERENCES plans(id) ON DELETE RESTRICT,
      title TEXT NOT NULL CHECK(length(trim(title)) > 0),
      note TEXT,
      status TEXT NOT NULL CHECK(status IN ('draft','next','dispatched','done','dropped')),
      sort_order INTEGER NOT NULL,
      created_at_utc INTEGER NOT NULL,
      updated_at_utc INTEGER NOT NULL
    )''');
    await _createPlanReviewNotes(database);
  }

  static Future<void> _createPlanReviewNotes(Database database) =>
      database.execute('''CREATE TABLE IF NOT EXISTS plan_review_notes (
      id TEXT PRIMARY KEY,
      plan_id TEXT NOT NULL REFERENCES plans(id) ON DELETE RESTRICT,
      content TEXT NOT NULL CHECK(length(trim(content)) > 0),
      created_at_utc INTEGER NOT NULL,
      updated_at_utc INTEGER NOT NULL,
      CHECK(updated_at_utc >= created_at_utc)
    )''');

  static Future<void> _migratePlanningAttention(Database database) async {
    final hasWorldNodes = await _tableExists(database, 'world_nodes');
    if (hasWorldNodes) {
      final worldColumns = await database.rawQuery(
        'PRAGMA table_info(world_nodes)',
      );
      final hasAttention = worldColumns.any(
        (row) => row['name'] == 'is_focused',
      );
      if (!hasAttention) {
        await database.execute(
          'ALTER TABLE world_nodes ADD COLUMN is_focused INTEGER NOT NULL DEFAULT 0 CHECK(is_focused IN (0,1))',
        );
      }
    }

    // Preserve metadata timestamps: attention is the normalized ownership of
    // the old current Plan status, not a new user edit during migration.
    await database.execute('DROP TRIGGER IF EXISTS world_nodes_sync_update');
    final hasPlans = await _tableExists(database, 'plans');
    if (hasWorldNodes && hasPlans) {
      await database.execute('''UPDATE world_nodes SET is_focused = CASE
        WHEN status = 'inProgress' AND EXISTS(
          SELECT 1 FROM plans
          WHERE plans.world_node_id = world_nodes.id
            AND plans.status = 'focused'
        ) THEN 1 ELSE 0 END''');
    }

    final hasItems = await _tableExists(database, 'plan_items');
    final hasNotes = await _tableExists(database, 'plan_review_notes');
    final hasEvents = await _tableExists(database, 'events');
    final hasSegments = await _tableExists(database, 'run_segments');
    final hasDayPlans = await _tableExists(database, 'event_day_plans');
    final plans = hasPlans ? await database.query('plans') : const [];
    final items = hasItems ? await database.query('plan_items') : const [];
    final notes = hasNotes
        ? await database.query('plan_review_notes')
        : const [];
    final events = hasEvents ? await database.query('events') : const [];
    final segments = hasSegments
        ? await database.query('run_segments')
        : const [];
    final dayPlans = hasDayPlans
        ? await database.query('event_day_plans')
        : const [];

    // SQLite cannot replace a CHECK constraint in place. Rebuild the complete
    // dependent chain child-first so every foreign key remains valid and no
    // delete trigger is interpreted as a business deletion.
    if (hasSegments) await database.execute('DROP TABLE run_segments');
    if (hasDayPlans) await database.execute('DROP TABLE event_day_plans');
    if (hasEvents) await database.execute('DROP TABLE events');
    if (hasNotes) await database.execute('DROP TABLE plan_review_notes');
    if (hasItems) await database.execute('DROP TABLE plan_items');
    if (hasPlans) await database.execute('DROP TABLE plans');

    await _createPlanningTables(database);
    if (hasEvents) await _createFlatEventTable(database, 'events');
    if (hasSegments) await _createRunSegments(database);
    if (hasDayPlans) await _createEventDayPlans(database);
    for (final source in plans) {
      final row = Map<String, Object?>.from(source);
      if (row['status'] != 'ended') row['status'] = 'current';
      await database.insert('plans', row);
    }
    for (final row in items) {
      await database.insert('plan_items', row);
    }
    for (final row in notes) {
      await database.insert('plan_review_notes', row);
    }
    for (final row in events) {
      await database.insert('events', row);
    }
    for (final row in segments) {
      await database.insert('run_segments', row);
    }
    for (final row in dayPlans) {
      await database.insert('event_day_plans', row);
    }
    await _createSyncTriggers(database);
  }

  static Future<void> _migrateToWaitingStatus(Database database) async {
    await database.execute('''CREATE TABLE events_v5 (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL CHECK(length(trim(name)) > 0),
      status TEXT NOT NULL CHECK(status IN ('pending','running','paused','waiting','completed')),
      parent_event_id TEXT REFERENCES events_v5(id) ON DELETE RESTRICT,
      sort_order INTEGER,
      first_started_at_utc INTEGER,
      completed_at_utc INTEGER,
      created_at_utc INTEGER NOT NULL,
      updated_at_utc INTEGER NOT NULL
    )''');
    await database.execute('''CREATE TABLE run_segments_v5 (
      id TEXT PRIMARY KEY,
      event_id TEXT NOT NULL REFERENCES events_v5(id) ON DELETE CASCADE,
      started_at_utc INTEGER NOT NULL,
      ended_at_utc INTEGER,
      created_at_utc INTEGER NOT NULL
    )''');
    await database.execute('''INSERT INTO events_v5 (
      id, name, status, parent_event_id, sort_order, first_started_at_utc,
      completed_at_utc, created_at_utc, updated_at_utc)
      SELECT id, name, status, parent_event_id, sort_order,
        first_started_at_utc, completed_at_utc, created_at_utc, updated_at_utc
      FROM events''');
    await database.execute(
      'INSERT INTO run_segments_v5 SELECT * FROM run_segments',
    );
    await database.execute('DROP TABLE run_segments');
    // Break the old table's self-references only after the complete copy exists.
    await database.execute('UPDATE events SET parent_event_id = NULL');
    await database.execute('DROP TABLE events');
    await database.execute('ALTER TABLE events_v5 RENAME TO events');
    await database.execute(
      'ALTER TABLE run_segments_v5 RENAME TO run_segments',
    );
  }

  static Future<void> _createRunSegments(Database database) =>
      database.execute('''CREATE TABLE run_segments (
    id TEXT PRIMARY KEY,
    event_id TEXT NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    started_at_utc INTEGER NOT NULL,
    ended_at_utc INTEGER,
    created_at_utc INTEGER NOT NULL,
    updated_at_utc INTEGER NOT NULL DEFAULT 0
  )''');

  static Future<void> _createLegacyRunSegments(Database database) =>
      database.execute('''CREATE TABLE run_segments (
    id TEXT PRIMARY KEY,
    event_id TEXT NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    started_at_utc INTEGER NOT NULL,
    ended_at_utc INTEGER,
    created_at_utc INTEGER NOT NULL
  )''');

  static Future<void> _createRoutineTables(Database database) async {
    await database.execute('''CREATE TABLE routines (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL CHECK(length(trim(name)) > 0),
      routine_category_id TEXT REFERENCES routine_categories(id) ON DELETE SET NULL,
      routine_type TEXT NOT NULL DEFAULT 'scheduled' CHECK(routine_type IN ('scheduled','onDemand')),
      recurrence_type TEXT NOT NULL CHECK(recurrence_type IN ('daily','weekdays','weekends','selectedWeekdays')),
      weekday_mask INTEGER NOT NULL DEFAULT 0,
      is_active INTEGER NOT NULL CHECK(is_active IN (0,1)),
      sort_order INTEGER NOT NULL,
      created_at_utc INTEGER NOT NULL,
      updated_at_utc INTEGER NOT NULL DEFAULT 0
    )''');
    await database.execute('''CREATE TABLE routine_executions (
      id TEXT PRIMARY KEY,
      routine_id TEXT NOT NULL REFERENCES routines(id) ON DELETE RESTRICT,
      occurrence_date TEXT NOT NULL,
      status TEXT NOT NULL CHECK(status IN ('running','paused','completed')),
      completed_at_utc INTEGER,
      created_at_utc INTEGER NOT NULL,
      updated_at_utc INTEGER NOT NULL
    )''');
    await database.execute('''CREATE TABLE routine_run_segments (
      id TEXT PRIMARY KEY,
      routine_execution_id TEXT NOT NULL REFERENCES routine_executions(id) ON DELETE CASCADE,
      started_at_utc INTEGER NOT NULL,
      ended_at_utc INTEGER,
      created_at_utc INTEGER NOT NULL,
      updated_at_utc INTEGER NOT NULL DEFAULT 0
    )''');
  }

  static Future<void> _migrateToOnDemandRoutines(Database database) async {
    final tables = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'routines'",
    );
    if (tables.isEmpty) return;
    final columns = await database.rawQuery('PRAGMA table_info(routines)');
    if (columns.any((column) => column['name'] == 'routine_type')) return;
    await database.execute(
      "ALTER TABLE routines ADD COLUMN routine_type TEXT NOT NULL DEFAULT 'scheduled' CHECK(routine_type IN ('scheduled','onDemand'))",
    );
    await database.execute('''CREATE TABLE routine_executions_v12 (
      id TEXT PRIMARY KEY,
      routine_id TEXT NOT NULL REFERENCES routines(id) ON DELETE RESTRICT,
      occurrence_date TEXT NOT NULL,
      status TEXT NOT NULL CHECK(status IN ('running','paused','completed')),
      completed_at_utc INTEGER,
      created_at_utc INTEGER NOT NULL,
      updated_at_utc INTEGER NOT NULL
    )''');
    await database.execute('''INSERT INTO routine_executions_v12
      SELECT id, routine_id, occurrence_date, status, completed_at_utc,
        created_at_utc, updated_at_utc FROM routine_executions''');
    await database.execute('''CREATE TABLE routine_run_segments_v12 (
      id TEXT PRIMARY KEY,
      routine_execution_id TEXT NOT NULL REFERENCES routine_executions_v12(id) ON DELETE CASCADE,
      started_at_utc INTEGER NOT NULL,
      ended_at_utc INTEGER,
      created_at_utc INTEGER NOT NULL
    )''');
    await database.execute('''INSERT INTO routine_run_segments_v12
      SELECT * FROM routine_run_segments''');
    await database.execute('DROP TABLE routine_run_segments');
    await database.execute('DROP TABLE routine_executions');
    await database.execute(
      'ALTER TABLE routine_executions_v12 RENAME TO routine_executions',
    );
    await database.execute(
      'ALTER TABLE routine_run_segments_v12 RENAME TO routine_run_segments',
    );
  }

  static Future<void> _createEventDayPlans(Database database) =>
      database.execute('''CREATE TABLE event_day_plans (
        event_id TEXT NOT NULL REFERENCES events(id) ON DELETE CASCADE,
        day_date TEXT NOT NULL,
        order_index INTEGER NOT NULL,
        created_at_utc INTEGER NOT NULL,
        updated_at_utc INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(event_id, day_date)
      )''');

  static Future<void> _createJaxDayCarryOverInitializations(
    Database database,
  ) => database.execute('''CREATE TABLE IF NOT EXISTS jax_day_carry_over_initializations (
        day_date TEXT PRIMARY KEY,
        initialized_at_utc INTEGER NOT NULL
      )''');

  static Future<void> _createSyncMetadata(Database database) async {
    await database.execute('''CREATE TABLE sync_tombstones (
      entity_type TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      deleted_at_utc INTEGER NOT NULL,
      PRIMARY KEY(entity_type, entity_id)
    )''');
    await _createSyncTriggers(database);
  }

  static Future<void> _migrateToSyncMetadata(Database database) async {
    for (final table in [
      'run_segments',
      'routine_run_segments',
      'event_day_plans',
    ]) {
      if (await _addColumnIfMissing(
        database,
        table,
        'updated_at_utc',
        'INTEGER',
      )) {
        await database.execute(
          'UPDATE $table SET updated_at_utc = created_at_utc',
        );
      }
    }
    await database.execute('''CREATE TABLE sync_tombstones (
      entity_type TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      deleted_at_utc INTEGER NOT NULL,
      PRIMARY KEY(entity_type, entity_id)
    )''');
    await _createSyncTriggers(database);
  }

  static Future<bool> _addColumnIfMissing(
    Database database,
    String table,
    String column,
    String type,
  ) async {
    final columns = await database.rawQuery('PRAGMA table_info($table)');
    if (columns.isEmpty) return false;
    if (!columns.any((row) => row['name'] == column)) {
      await database.execute('ALTER TABLE $table ADD COLUMN $column $type');
    }
    return true;
  }

  static Future<void> _createSyncTriggers(Database database) async {
    const entities = <String, String>{
      'categories': 'category',
      'events': 'event',
      'run_segments': 'eventRunSegment',
      'routine_categories': 'routineCategory',
      'routines': 'routine',
      'routine_executions': 'routineExecution',
      'routine_run_segments': 'routineRunSegment',
      'world_nodes': 'worldNode',
      'legacy_event_world_node_links': 'legacyEventWorldNodeLink',
      'plans': 'plan',
      'plan_items': 'planItem',
      'plan_review_notes': 'planReviewNote',
    };
    for (final entry in entities.entries) {
      if (!await _tableExists(database, entry.key)) continue;
      await database.execute(
        '''CREATE TRIGGER IF NOT EXISTS ${entry.key}_sync_delete
        AFTER DELETE ON ${entry.key}
        BEGIN
          INSERT OR REPLACE INTO sync_tombstones(entity_type, entity_id, deleted_at_utc)
          VALUES('${entry.value}', OLD.id,
            CAST((julianday('now') - 2440587.5) * 86400000 AS INTEGER));
        END''',
      );
      await database.execute(
        '''CREATE TRIGGER IF NOT EXISTS ${entry.key}_sync_insert
        AFTER INSERT ON ${entry.key}
        BEGIN
          UPDATE ${entry.key} SET updated_at_utc = created_at_utc
          WHERE rowid = NEW.rowid AND updated_at_utc = 0;
          DELETE FROM sync_tombstones
          WHERE entity_type = '${entry.value}' AND entity_id = NEW.id;
        END''',
      );
    }
    if (await _tableExists(database, 'event_day_plans')) {
      await database.execute(
        '''CREATE TRIGGER IF NOT EXISTS event_day_plans_sync_delete
      AFTER DELETE ON event_day_plans
      BEGIN
        INSERT OR REPLACE INTO sync_tombstones(entity_type, entity_id, deleted_at_utc)
        VALUES('eventDayPlan', OLD.event_id || '@' || OLD.day_date,
          CAST((julianday('now') - 2440587.5) * 86400000 AS INTEGER));
      END''',
      );
      await database.execute(
        '''CREATE TRIGGER IF NOT EXISTS event_day_plans_sync_insert
      AFTER INSERT ON event_day_plans
      BEGIN
        UPDATE event_day_plans SET updated_at_utc = created_at_utc
        WHERE rowid = NEW.rowid AND updated_at_utc = 0;
        DELETE FROM sync_tombstones
        WHERE entity_type = 'eventDayPlan'
          AND entity_id = NEW.event_id || '@' || NEW.day_date;
      END''',
      );
    }

    const timestampTables = <String>[
      'categories',
      'events',
      'run_segments',
      'routine_categories',
      'routines',
      'routine_executions',
      'routine_run_segments',
      'event_day_plans',
      'world_nodes',
      'legacy_event_world_node_links',
      'plans',
      'plan_items',
      'plan_review_notes',
    ];
    for (final table in timestampTables) {
      final columns = await database.rawQuery('PRAGMA table_info($table)');
      if (!columns.any((row) => row['name'] == 'updated_at_utc')) continue;
      await database.execute(
        '''CREATE TRIGGER IF NOT EXISTS ${table}_sync_update
        AFTER UPDATE ON $table
        WHEN NEW.updated_at_utc = OLD.updated_at_utc
        BEGIN
          UPDATE $table SET updated_at_utc =
            MAX(OLD.updated_at_utc + 1,
              CAST((julianday('now') - 2440587.5) * 86400000 AS INTEGER))
          WHERE rowid = NEW.rowid;
        END''',
      );
    }
  }

  static Future<bool> _tableExists(Database database, String table) async =>
      (await database.rawQuery(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
        [table],
      )).isNotEmpty;

  static Future<void> _createWorldCategoryCollapsePreferences(
    Database database,
  ) => database.execute('''CREATE TABLE world_category_collapse_preferences (
        section_key TEXT PRIMARY KEY
      )''');

  static Future<void> _createRoutineCategoryTables(Database database) async {
    await database.execute('''CREATE TABLE routine_categories (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL UNIQUE CHECK(length(trim(name)) > 0),
      sort_order INTEGER NOT NULL,
      color_key INTEGER NOT NULL CHECK(color_key BETWEEN 0 AND 7),
      created_at_utc INTEGER NOT NULL,
      updated_at_utc INTEGER NOT NULL
    )''');
    await database.execute(
      '''CREATE TABLE routine_category_collapse_preferences (
      section_key TEXT PRIMARY KEY
    )''',
    );
  }

  static Future<void> _migrateToRoutineCategories(Database database) async {
    await _createRoutineCategoryTables(database);
    final routineTable = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'routines'",
    );
    if (routineTable.isEmpty) {
      await _createRoutineTables(database);
      return;
    }
    final columns = await database.rawQuery('PRAGMA table_info(routines)');
    if (!columns.any((row) => row['name'] == 'routine_category_id')) {
      await database.execute(
        'ALTER TABLE routines ADD COLUMN routine_category_id TEXT REFERENCES routine_categories(id) ON DELETE SET NULL',
      );
    }
    // Old World Category assignments are deliberately not copied.
    await database.execute('UPDATE routines SET routine_category_id = NULL');
  }

  static Future<void> _migrateToCategoryColors(Database database) async {
    final eventColumns = await database.rawQuery(
      'PRAGMA table_info(categories)',
    );
    final routineColumns = await database.rawQuery(
      'PRAGMA table_info(routine_categories)',
    );
    if (eventColumns.isNotEmpty &&
        !eventColumns.any((row) => row['name'] == 'color_key')) {
      await database.execute(
        'ALTER TABLE categories ADD COLUMN color_key INTEGER NOT NULL DEFAULT 0 CHECK(color_key BETWEEN 0 AND 7)',
      );
    }
    if (routineColumns.isNotEmpty &&
        !routineColumns.any((row) => row['name'] == 'color_key')) {
      await database.execute(
        'ALTER TABLE routine_categories ADD COLUMN color_key INTEGER NOT NULL DEFAULT 0 CHECK(color_key BETWEEN 0 AND 7)',
      );
    }
    var paletteIndex = 0;
    final eventCategories = eventColumns.isEmpty
        ? const <Map<String, Object?>>[]
        : await database.query(
            'categories',
            columns: ['id'],
            orderBy: 'sort_order ASC, created_at_utc ASC, id ASC',
          );
    for (final category in eventCategories) {
      await database.update(
        'categories',
        {'color_key': paletteIndex % 8},
        where: 'id = ?',
        whereArgs: [category['id']],
      );
      paletteIndex++;
    }
    final routineCategories = routineColumns.isEmpty
        ? const <Map<String, Object?>>[]
        : await database.query(
            'routine_categories',
            columns: ['id'],
            orderBy: 'sort_order ASC, created_at_utc ASC, id ASC',
          );
    for (final category in routineCategories) {
      await database.update(
        'routine_categories',
        {'color_key': paletteIndex % 8},
        where: 'id = ?',
        whereArgs: [category['id']],
      );
      paletteIndex++;
    }
  }

  Future<void> close() => database.close();
}
