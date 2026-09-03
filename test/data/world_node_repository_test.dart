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
}

WorldNode _node(String id, String name, int order, {String? parent}) =>
    WorldNode(
      id: id,
      name: name,
      status: WorldNodeStatus.inProgress,
      isFocused: false,
      parentWorldNodeId: parent,
      sortOrder: order,
      createdAt: _time(10),
      updatedAt: _time(10),
    );

DateTime _time(int milliseconds) =>
    DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
