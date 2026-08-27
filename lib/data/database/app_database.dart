import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class AppDatabase {
  AppDatabase._(this.database);
  final Database database;
  static const schemaVersion = 9;

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
      created_at_utc INTEGER NOT NULL,
      updated_at_utc INTEGER NOT NULL
    )''');
    await database.execute('''CREATE TABLE events (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL CHECK(length(trim(name)) > 0),
      status TEXT NOT NULL CHECK(status IN ('pending','running','paused','waiting','completed')),
      parent_event_id TEXT REFERENCES events(id) ON DELETE RESTRICT,
      sort_order INTEGER,
      category_id TEXT REFERENCES categories(id) ON DELETE SET NULL,
      first_started_at_utc INTEGER,
      completed_at_utc INTEGER,
      created_at_utc INTEGER NOT NULL,
      updated_at_utc INTEGER NOT NULL
    )''');
    await _createRunSegments(database);
    await _createRoutineTables(database);
    await _createEventDayPlans(database);
    await _createWorldCategoryCollapsePreferences(database);
  }

  static Future<void> _upgradeSchema(
    Database database,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) await _createRunSegments(database);
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
    created_at_utc INTEGER NOT NULL
  )''');

  static Future<void> _createRoutineTables(Database database) async {
    await database.execute('''CREATE TABLE routines (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL CHECK(length(trim(name)) > 0),
      category_id TEXT REFERENCES categories(id) ON DELETE SET NULL,
      recurrence_type TEXT NOT NULL CHECK(recurrence_type IN ('daily','weekdays','weekends','selectedWeekdays')),
      weekday_mask INTEGER NOT NULL DEFAULT 0,
      is_active INTEGER NOT NULL CHECK(is_active IN (0,1)),
      sort_order INTEGER NOT NULL,
      created_at_utc INTEGER NOT NULL,
      updated_at_utc INTEGER NOT NULL
    )''');
    await database.execute('''CREATE TABLE routine_executions (
      id TEXT PRIMARY KEY,
      routine_id TEXT NOT NULL REFERENCES routines(id) ON DELETE RESTRICT,
      occurrence_date TEXT NOT NULL,
      status TEXT NOT NULL CHECK(status IN ('running','paused','completed')),
      completed_at_utc INTEGER,
      created_at_utc INTEGER NOT NULL,
      updated_at_utc INTEGER NOT NULL,
      UNIQUE(routine_id, occurrence_date)
    )''');
    await database.execute('''CREATE TABLE routine_run_segments (
      id TEXT PRIMARY KEY,
      routine_execution_id TEXT NOT NULL REFERENCES routine_executions(id) ON DELETE CASCADE,
      started_at_utc INTEGER NOT NULL,
      ended_at_utc INTEGER,
      created_at_utc INTEGER NOT NULL
    )''');
  }

  static Future<void> _createEventDayPlans(Database database) =>
      database.execute('''CREATE TABLE event_day_plans (
        event_id TEXT NOT NULL REFERENCES events(id) ON DELETE CASCADE,
        day_date TEXT NOT NULL,
        order_index INTEGER NOT NULL,
        created_at_utc INTEGER NOT NULL,
        PRIMARY KEY(event_id, day_date)
      )''');

  static Future<void> _createWorldCategoryCollapsePreferences(
    Database database,
  ) => database.execute('''CREATE TABLE world_category_collapse_preferences (
        section_key TEXT PRIMARY KEY
      )''');

  Future<void> close() => database.close();
}
