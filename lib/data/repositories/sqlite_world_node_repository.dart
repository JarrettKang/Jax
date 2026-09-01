import 'package:sqflite/sqflite.dart';

import '../../core/entities/world_node.dart';
import '../../core/entities/world_node_ids.dart';
import '../../core/repositories/world_node_repository.dart';
import '../database/app_database.dart';

class SqliteWorldNodeRepository implements WorldNodeRepository {
  const SqliteWorldNodeRepository(this._database);

  final AppDatabase _database;

  @override
  Future<List<WorldNode>> getWorldNodes() async =>
      (await _database.database.query(
        'world_nodes',
        orderBy: 'sort_order, created_at_utc, id',
      )).map(_nodeFromRow).toList(growable: false);

  @override
  Future<WorldNode?> getWorldNode(String id) async {
    final rows = await _database.database.query(
      'world_nodes',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : _nodeFromRow(rows.single);
  }

  @override
  Future<List<LegacyEventWorldNodeLink>> getLegacyLinks() async =>
      (await _database.database.query(
        'legacy_event_world_node_links',
        orderBy: 'legacy_event_id',
      )).map(_linkFromRow).toList(growable: false);

  @override
  Future<void> insertWorldNode(WorldNode node) async {
    await _database.database.transaction((transaction) async {
      await _validatePlacement(
        transaction,
        node.id,
        node.parentWorldNodeId,
        node.categoryId,
      );
      await transaction.insert('world_nodes', _nodeToRow(node));
    });
  }

  @override
  Future<void> updateWorldNode(WorldNode node) async {
    await _database.database.transaction((transaction) async {
      if (node.status == WorldNodeStatus.completed &&
          await _hasCurrentPlan(transaction, node.id)) {
        throw StateError('End the current Plan before completing WorldNode');
      }
      await _validatePlacement(
        transaction,
        node.id,
        node.parentWorldNodeId,
        node.categoryId,
      );
      if (await transaction.update(
            'world_nodes',
            _nodeToRow(node),
            where: 'id = ?',
            whereArgs: [node.id],
          ) !=
          1) {
        throw StateError('WorldNode not found: ${node.id}');
      }
    });
  }

  Future<bool> _hasCurrentPlan(DatabaseExecutor db, String worldNodeId) async {
    final tables = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'plans'",
    );
    if (tables.isEmpty) return false;
    return (await db.query(
      'plans',
      columns: ['id'],
      where: "world_node_id = ? AND status IN ('focused','waiting')",
      whereArgs: [worldNodeId],
      limit: 1,
    )).isNotEmpty;
  }

  @override
  Future<void> reparentWorldNode(
    String id,
    String? parentWorldNodeId,
    String? categoryId,
    int sortOrder,
    DateTime updatedAt,
  ) async {
    await _database.database.transaction((transaction) async {
      await _validatePlacement(transaction, id, parentWorldNodeId, categoryId);
      if (await transaction.update(
            'world_nodes',
            {
              'parent_world_node_id': parentWorldNodeId,
              'category_id': parentWorldNodeId == null ? categoryId : null,
              'sort_order': sortOrder,
              'updated_at_utc': updatedAt.toUtc().millisecondsSinceEpoch,
            },
            where: 'id = ?',
            whereArgs: [id],
          ) !=
          1) {
        throw StateError('WorldNode not found: $id');
      }
    });
  }

  @override
  Future<void> reorderWorldNode(String id, int targetIndex) async {
    await _database.database.transaction((transaction) async {
      final currentRows = await transaction.query(
        'world_nodes',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (currentRows.isEmpty) throw StateError('WorldNode not found: $id');
      final current = currentRows.single;
      final parent = current['parent_world_node_id'] as String?;
      final category = current['category_id'] as String?;
      final where = parent == null
          ? category == null
                ? 'parent_world_node_id IS NULL AND category_id IS NULL'
                : 'parent_world_node_id IS NULL AND category_id = ?'
          : 'parent_world_node_id = ?';
      final args = parent == null
          ? category == null
                ? const <Object?>[]
                : <Object?>[category]
          : <Object?>[parent];
      final siblings = await transaction.query(
        'world_nodes',
        columns: ['id', 'updated_at_utc'],
        where: where,
        whereArgs: args,
        orderBy: 'sort_order, created_at_utc, id',
      );
      final currentIndex = siblings.indexWhere((row) => row['id'] == id);
      if (currentIndex < 0 ||
          targetIndex < 0 ||
          targetIndex >= siblings.length) {
        throw StateError('Invalid WorldNode reorder target');
      }
      final reordered = [...siblings];
      final moved = reordered.removeAt(currentIndex);
      reordered.insert(targetIndex, moved);
      for (var index = 0; index < reordered.length; index++) {
        await transaction.update(
          'world_nodes',
          {
            'sort_order': index,
            'updated_at_utc': reordered[index]['updated_at_utc'],
          },
          where: 'id = ?',
          whereArgs: [reordered[index]['id']],
        );
      }
    });
  }

  Future<void> _validatePlacement(
    DatabaseExecutor db,
    String id,
    String? parentId,
    String? categoryId,
  ) async {
    if (!WorldNodeIds.isValid(id)) {
      throw StateError('WorldNode id must be a UUID: $id');
    }
    if (parentId != null && categoryId != null) {
      throw StateError('Child WorldNode cannot own a direct Category');
    }
    if (parentId == id) throw StateError('WorldNode cannot parent itself');
    var cursor = parentId;
    final seen = <String>{id};
    while (cursor != null) {
      if (!seen.add(cursor)) throw StateError('WorldNode hierarchy cycle');
      final rows = await db.query(
        'world_nodes',
        columns: ['parent_world_node_id'],
        where: 'id = ?',
        whereArgs: [cursor],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('WorldNode parent not found: $cursor');
      cursor = rows.single['parent_world_node_id'] as String?;
    }
  }

  Map<String, Object?> _nodeToRow(WorldNode node) => {
    'id': node.id,
    'name': node.name,
    'status': node.status.name,
    'parent_world_node_id': node.parentWorldNodeId,
    'sort_order': node.sortOrder,
    'category_id': node.parentWorldNodeId == null ? node.categoryId : null,
    'created_at_utc': node.createdAt.toUtc().millisecondsSinceEpoch,
    'updated_at_utc': node.updatedAt.toUtc().millisecondsSinceEpoch,
  };

  WorldNode _nodeFromRow(Map<String, Object?> row) => WorldNode(
    id: row['id']! as String,
    name: row['name']! as String,
    status: WorldNodeStatus.values.byName(row['status']! as String),
    parentWorldNodeId: row['parent_world_node_id'] as String?,
    categoryId: row['category_id'] as String?,
    sortOrder: (row['sort_order']! as num).toInt(),
    createdAt: _date(row['created_at_utc']),
    updatedAt: _date(row['updated_at_utc']),
  );

  LegacyEventWorldNodeLink _linkFromRow(Map<String, Object?> row) =>
      LegacyEventWorldNodeLink(
        legacyEventId: row['legacy_event_id']! as String,
        worldNodeId: row['world_node_id']! as String,
        createdAt: _date(row['created_at_utc']),
        updatedAt: _date(row['updated_at_utc']),
      );

  DateTime _date(Object? value) =>
      DateTime.fromMillisecondsSinceEpoch((value! as num).toInt(), isUtc: true);
}
