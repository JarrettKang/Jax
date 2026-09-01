import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/entities/world_node_ids.dart';

class WorldNodeShadowMigration {
  const WorldNodeShadowMigration._();

  static Future<void> createTables(DatabaseExecutor db) async {
    await createWorldNodeTable(db);
    await createLegacyLinkTable(db);
  }

  static Future<void> createWorldNodeTable(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS world_nodes (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL CHECK(length(trim(name)) > 0),
      status TEXT NOT NULL CHECK(status IN ('inProgress','completed')),
      parent_world_node_id TEXT REFERENCES world_nodes(id) ON DELETE RESTRICT,
      sort_order INTEGER NOT NULL,
      category_id TEXT REFERENCES categories(id) ON DELETE SET NULL,
      created_at_utc INTEGER NOT NULL,
      updated_at_utc INTEGER NOT NULL
    )''');
  }

  static Future<void> createLegacyLinkTable(DatabaseExecutor db) async {
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS legacy_event_world_node_links (
      id TEXT PRIMARY KEY,
      legacy_event_id TEXT NOT NULL UNIQUE REFERENCES events(id) ON DELETE CASCADE,
      world_node_id TEXT NOT NULL UNIQUE REFERENCES world_nodes(id) ON DELETE CASCADE,
      created_at_utc INTEGER NOT NULL,
      updated_at_utc INTEGER NOT NULL,
      CHECK(id = legacy_event_id)
    )''',
    );
  }

  static Future<void> run(Database database, {int? failAfterInsert}) =>
      database.transaction(
        (transaction) =>
            backfill(transaction, failAfterInsert: failAfterInsert),
      );

  static Future<void> backfill(
    DatabaseExecutor db, {
    int? failAfterInsert,
  }) async {
    await createTables(db);
    // Some historical migration tests intentionally use a partial schema that
    // contains only the table under test. A real Jax database always has both
    // tables by v6; skip shadow data only for those synthetic partial schemas.
    if (!await _tableExists(db, 'events') ||
        !await _tableExists(db, 'categories')) {
      return;
    }
    final rows = await db.query('events');
    final byId = {
      for (final row in rows)
        row['id']! as String: Map<String, Object?>.from(row),
    };
    _validateLegacyHierarchy(byId);
    final ordered = rows.map(Map<String, Object?>.from).toList()
      ..sort(_eventOrder);
    final scopeIndexes = <String, int>{};
    final orderById = <String, int>{};
    for (final event in ordered) {
      final parent = event['parent_event_id'] as String?;
      final scope = parent == null
          ? 'category:${event['category_id'] ?? 'uncategorized'}'
          : 'parent:$parent';
      orderById[event['id']! as String] = scopeIndexes[scope] ?? 0;
      scopeIndexes[scope] = (scopeIndexes[scope] ?? 0) + 1;
    }
    final depths = <String, int>{};
    int depthOf(String id) =>
        depths[id] ??= switch (byId[id]!['parent_event_id'] as String?) {
          null => 0,
          final parent => depthOf(parent) + 1,
        };
    ordered.sort((a, b) {
      final depth = depthOf(a['id']! as String)
          .compareTo(depthOf(b['id']! as String));
      return depth != 0 ? depth : _eventOrder(a, b);
    });

    var inserted = 0;
    for (final event in ordered) {
      final legacyId = event['id']! as String;
      final worldNodeId = WorldNodeIds.fromLegacyEvent(legacyId);
      final parentLegacyId = event['parent_event_id'] as String?;
      final nodeRow = <String, Object?>{
        'id': worldNodeId,
        'name': event['name'],
        'status': event['status'] == 'completed' ? 'completed' : 'inProgress',
        'parent_world_node_id': parentLegacyId == null
            ? null
            : WorldNodeIds.fromLegacyEvent(parentLegacyId),
        'sort_order': orderById[legacyId],
        'category_id': parentLegacyId == null ? event['category_id'] : null,
        'created_at_utc': event['created_at_utc'],
        'updated_at_utc': event['updated_at_utc'],
      };
      final changed = await db.insert(
        'world_nodes',
        nodeRow,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      if (changed != 0) inserted++;
      await db.insert('legacy_event_world_node_links', {
        'id': legacyId,
        'legacy_event_id': legacyId,
        'world_node_id': worldNodeId,
        'created_at_utc': event['created_at_utc'],
        'updated_at_utc': event['updated_at_utc'],
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      final links = await db.query(
        'legacy_event_world_node_links',
        columns: ['world_node_id'],
        where: 'legacy_event_id = ?',
        whereArgs: [legacyId],
      );
      if (links.length != 1 || links.single['world_node_id'] != worldNodeId) {
        throw StateError('Invalid legacy mapping for Event $legacyId');
      }
      if (failAfterInsert != null && inserted == failAfterInsert) {
        throw StateError('Injected WorldNode migration failure');
      }
    }
  }

  static Future<bool> _tableExists(DatabaseExecutor db, String table) async =>
      (await db.rawQuery(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
        [table],
      )).isNotEmpty;

  static void _validateLegacyHierarchy(
    Map<String, Map<String, Object?>> events,
  ) {
    for (final event in events.values) {
      final id = event['id']! as String;
      final parent = event['parent_event_id'] as String?;
      if (parent != null && !events.containsKey(parent)) {
        throw StateError('Legacy Event $id has missing parent $parent');
      }
      final seen = <String>{id};
      var cursor = parent;
      while (cursor != null) {
        if (!seen.add(cursor)) {
          throw StateError('Legacy Event hierarchy cycle at $id');
        }
        cursor = events[cursor]!['parent_event_id'] as String?;
      }
    }
  }

  static int _eventOrder(
    Map<String, Object?> left,
    Map<String, Object?> right,
  ) {
    final leftOrder = left['sort_order'] as int?;
    final rightOrder = right['sort_order'] as int?;
    if (leftOrder != null || rightOrder != null) {
      if (leftOrder == null) return 1;
      if (rightOrder == null) return -1;
      final order = leftOrder.compareTo(rightOrder);
      if (order != 0) return order;
    }
    final created = (left['created_at_utc']! as int).compareTo(
      right['created_at_utc']! as int,
    );
    return created != 0
        ? created
        : (left['id']! as String).compareTo(right['id']! as String);
  }
}
