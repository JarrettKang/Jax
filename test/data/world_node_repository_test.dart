import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/world_node.dart';
import 'package:jax/core/entities/world_node_ids.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/database/world_node_shadow_migration.dart';
import 'package:jax/data/repositories/sqlite_world_node_repository.dart';

void main() {
  late AppDatabase app;
  late SqliteWorldNodeRepository repository;
  setUp(() async {
    app = await AppDatabase.inMemory();
    repository = SqliteWorldNodeRepository(app);
  });
  tearDown(() => app.close());

  test('legacy Event and migrated WorldNode status are decoupled', () async {
    await app.database.insert('events', {
      'id': 'legacy',
      'name': '优化界面和操作',
      'status': 'completed',
      'sort_order': 0,
      'completed_at_utc': 100,
      'created_at_utc': 10,
      'updated_at_utc': 100,
    });
    await WorldNodeShadowMigration.run(app.database);
    final id = WorldNodeIds.fromLegacyEvent('legacy');
    expect(
      (await repository.getWorldNode(id))!.status,
      WorldNodeStatus.completed,
    );

    await app.database.update(
      'events',
      {'status': 'paused', 'completed_at_utc': null, 'updated_at_utc': 200},
      where: 'id = ?',
      whereArgs: ['legacy'],
    );
    expect(
      (await repository.getWorldNode(id))!.status,
      WorldNodeStatus.completed,
    );

    final node = (await repository.getWorldNode(id))!;
    await repository.updateWorldNode(
      node.copyWith(status: WorldNodeStatus.inProgress, updatedAt: _time(300)),
    );
    expect(
      (await app.database.query(
        'events',
        where: 'id = ?',
        whereArgs: ['legacy'],
      )).single['status'],
      'paused',
    );
  });

  test('repository enforces hierarchy and scoped reorder', () async {
    final rootA = _node('11111111-1111-4111-8111-111111111111', 'A', 0);
    final rootB = _node('22222222-2222-4222-8222-222222222222', 'B', 1);
    final child = _node(
      '33333333-3333-4333-8333-333333333333',
      'Child',
      0,
      parent: rootA.id,
    );
    await repository.insertWorldNode(rootA);
    await repository.insertWorldNode(rootB);
    await repository.insertWorldNode(child);

    await repository.reorderWorldNode(rootB.id, 0);
    final roots =
        (await repository.getWorldNodes())
            .where((node) => node.parentWorldNodeId == null)
            .toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    expect(roots.map((node) => node.id), [rootB.id, rootA.id]);

    await expectLater(
      repository.reparentWorldNode(rootA.id, child.id, null, 0, _time(400)),
      throwsStateError,
    );
    await repository.reparentWorldNode(child.id, null, null, 2, _time(500));
    expect(
      (await repository.getWorldNode(child.id))!.parentWorldNodeId,
      isNull,
    );
  });
}

WorldNode _node(String id, String name, int order, {String? parent}) =>
    WorldNode(
      id: id,
      name: name,
      status: WorldNodeStatus.inProgress,
      parentWorldNodeId: parent,
      sortOrder: order,
      createdAt: _time(10),
      updatedAt: _time(10),
    );

DateTime _time(int milliseconds) =>
    DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
