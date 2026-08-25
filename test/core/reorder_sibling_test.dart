import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/use_cases/reorder_sibling.dart';

import '../support/memory_repository.dart';

void main() {
  final time = DateTime.utc(2026, 8, 25, 8);
  JaxEvent event(String id, {String? parent, int? order}) => JaxEvent(
    id: id,
    name: id,
    status: EventStatus.pending,
    parentEventId: parent,
    sortOrder: order,
    createdAt: time,
    updatedAt: time,
  );

  test('reorders top-level siblings without changing hierarchy', () async {
    final repository = MemoryRepository([
      event('a', order: 0),
      event('b', order: 1),
      event('c', order: 2),
    ]);
    await ReorderSibling(repository)('c', 0);
    expect(
      (await repository.getOrderedTopLevelEvents()).map((item) => item.id),
      ['c', 'a', 'b'],
    );
    expect((await repository.getEvent('c'))?.parentEventId, isNull);
  });

  test(
    'reorders child siblings and completed status does not affect order',
    () async {
      final repository = MemoryRepository([
        event('parent'),
        event('a', parent: 'parent', order: 0),
        event('b', parent: 'parent', order: 1),
        event('c', parent: 'parent', order: 2),
      ]);
      await repository.updateEvent(
        (await repository.getEvent('b'))!
            .copyWith(status: EventStatus.completed),
      );
      await ReorderSibling(repository)('b', 2);
      expect(
        (await repository.getDirectChildren('parent')).map((item) => item.id),
        ['a', 'c', 'b'],
      );
    },
  );

  test('new event and hierarchy moves append to target collection', () async {
    final repository = MemoryRepository([
      event('a', order: 0),
      event('b', order: 1),
      event('parent', order: 2),
      event('child', parent: 'parent', order: 0),
    ]);
    await repository.insertEvent(event('new'));
    expect(
      (await repository.getOrderedTopLevelEvents()).map((item) => item.id),
      ['a', 'b', 'parent', 'new'],
    );
    await repository.updateParent('a', 'parent', time);
    expect(
      (await repository.getDirectChildren('parent')).map((item) => item.id),
      ['child', 'a'],
    );
    await repository.updateParent('a', null, time);
    expect(
      (await repository.getOrderedTopLevelEvents()).map((item) => item.id),
      ['b', 'parent', 'new', 'a'],
    );
  });

  test('invalid target index is rejected', () async {
    final repository = MemoryRepository([event('a', order: 0)]);
    await expectLater(
      ReorderSibling(repository)('a', 1),
      throwsA(isA<Exception>()),
    );
  });
}
