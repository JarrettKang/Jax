import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/world_node.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/repositories/sqlite_world_node_repository.dart';

void main() {
  late AppDatabase app;
  late SqliteWorldNodeRepository repository;
  setUp(() async {
    app = await AppDatabase.inMemory();
    repository = SqliteWorldNodeRepository(app);
  });
  tearDown(() => app.close());

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

  test('attention is local to each node and does not require a Plan', () async {
    final parent = _node('11111111-1111-4111-8111-111111111111', 'Parent', 0);
    final child = _node(
      '22222222-2222-4222-8222-222222222222',
      'Child',
      0,
      parent: parent.id,
    );
    await repository.insertWorldNode(parent);
    await repository.insertWorldNode(child);

    await repository.setWorldNodeFocus(child.id, true, _time(20));
    expect((await repository.getWorldNode(child.id))!.isFocused, isTrue);
    expect((await repository.getWorldNode(parent.id))!.isFocused, isFalse);

    await repository.setWorldNodeFocus(parent.id, true, _time(30));
    await repository.setWorldNodeFocus(child.id, false, _time(40));
    expect((await repository.getWorldNode(parent.id))!.isFocused, isTrue);
    expect((await repository.getWorldNode(child.id))!.isFocused, isFalse);
  });

  test(
    'completion clears attention and restoration remains unfocused',
    () async {
      final node = _node(
        '11111111-1111-4111-8111-111111111111',
        'Focused',
        0,
      ).copyWith(isFocused: true);
      await repository.insertWorldNode(node);

      await repository.updateWorldNode(
        node.copyWith(status: WorldNodeStatus.completed, updatedAt: _time(20)),
      );
      final completed = (await repository.getWorldNode(node.id))!;
      expect(completed.status, WorldNodeStatus.completed);
      expect(completed.isFocused, isFalse);
      await expectLater(
        repository.setWorldNodeFocus(node.id, true, _time(30)),
        throwsStateError,
      );

      await repository.updateWorldNode(
        completed.copyWith(
          status: WorldNodeStatus.inProgress,
          isFocused: true,
          updatedAt: _time(40),
        ),
      );
      final restored = (await repository.getWorldNode(node.id))!;
      expect(restored.status, WorldNodeStatus.inProgress);
      expect(restored.isFocused, isFalse);
    },
  );

  test(
    'reparent preserves attention and all Planning/Event execution facts',
    () async {
      final db = app.database;
      await db.insert('categories', {
        'id': 'category-a',
        'name': 'Category A',
        'sort_order': 0,
        'color_key': 0,
        'created_at_utc': 1,
        'updated_at_utc': 1,
      });
      await db.insert('categories', {
        'id': 'category-b',
        'name': 'Category B',
        'sort_order': 1,
        'color_key': 1,
        'created_at_utc': 1,
        'updated_at_utc': 1,
      });
      final rootA = _node(
        '11111111-1111-4111-8111-111111111111',
        'A',
        0,
        category: 'category-a',
      );
      final moving = _node(
        '22222222-2222-4222-8222-222222222222',
        'Focused child',
        0,
        parent: rootA.id,
        focused: true,
      );
      final rootB = _node(
        '33333333-3333-4333-8333-333333333333',
        'B',
        0,
        category: 'category-b',
      );
      final existingBChild = _node(
        '44444444-4444-4444-8444-444444444444',
        'Existing B child',
        0,
        parent: rootB.id,
      );
      for (final node in [rootA, moving, rootB, existingBChild]) {
        await repository.insertWorldNode(node);
      }
      await db.insert('plans', {
        'id': 'plan-1',
        'world_node_id': moving.id,
        'title': 'Current plan',
        'status': 'current',
        'round_number': 1,
        'ended_at_utc': null,
        'created_at_utc': 20,
        'updated_at_utc': 20,
      });
      await db.insert('plan_items', {
        'id': 'item-1',
        'plan_id': 'plan-1',
        'title': 'Dispatched item',
        'note': null,
        'status': 'dispatched',
        'sort_order': 0,
        'created_at_utc': 21,
        'updated_at_utc': 21,
      });
      await db.insert('events', {
        'id': 'event-1',
        'name': 'Linked event',
        'status': 'paused',
        'source_plan_item_id': 'item-1',
        'category_id': null,
        'first_started_at_utc': 30,
        'completed_at_utc': null,
        'created_at_utc': 22,
        'updated_at_utc': 30,
      });
      await db.insert('event_day_plans', {
        'event_id': 'event-1',
        'day_date': '2026-09-03',
        'order_index': 0,
        'created_at_utc': 23,
        'updated_at_utc': 23,
      });
      await db.insert('run_segments', {
        'id': 'segment-1',
        'event_id': 'event-1',
        'started_at_utc': 30,
        'ended_at_utc': 40,
        'created_at_utc': 30,
        'updated_at_utc': 40,
      });
      final before = await _businessSnapshot(app);

      await repository.reparentWorldNode(
        moving.id,
        rootB.id,
        null,
        1,
        _time(500),
      );
      final underB = (await repository.getWorldNode(moving.id))!;
      expect(underB.parentWorldNodeId, rootB.id);
      expect(underB.categoryId, isNull);
      expect(underB.sortOrder, 1);
      expect(underB.isFocused, isTrue);
      expect(
        (await repository.getWorldNode(rootB.id))!.categoryId,
        'category-b',
      );
      expect(await _businessSnapshot(app), equals(before));

      // The controller passes the effective category when moving a child to
      // root. The repository persists that existing product semantic.
      await repository.reparentWorldNode(
        moving.id,
        null,
        'category-b',
        1,
        _time(600),
      );
      final atRoot = (await repository.getWorldNode(moving.id))!;
      expect(atRoot.parentWorldNodeId, isNull);
      expect(atRoot.categoryId, 'category-b');
      expect(atRoot.sortOrder, 1);
      expect(atRoot.isFocused, isTrue);
      expect(await _businessSnapshot(app), equals(before));
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );
}

Future<Map<String, List<Map<String, Object?>>>> _businessSnapshot(
  AppDatabase app,
) async => {
  for (final table in [
    'plans',
    'plan_items',
    'events',
    'event_day_plans',
    'run_segments',
  ])
    table: await app.database.query(table, orderBy: 'rowid'),
};

WorldNode _node(
  String id,
  String name,
  int order, {
  String? parent,
  String? category,
  bool focused = false,
}) => WorldNode(
  id: id,
  name: name,
  status: WorldNodeStatus.inProgress,
  isFocused: focused,
  parentWorldNodeId: parent,
  categoryId: category,
  sortOrder: order,
  createdAt: _time(10),
  updatedAt: _time(10),
);

DateTime _time(int milliseconds) =>
    DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
