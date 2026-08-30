import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/errors/domain_failure.dart';
import 'package:jax/core/services/event_hierarchy_service.dart';
import 'package:jax/core/use_cases/delete_event.dart';
import 'package:jax/core/use_cases/delete_history_record.dart';
import 'package:jax/core/use_cases/update_event_parent.dart';

import '../support/memory_repository.dart';

void main() {
  final time = DateTime.utc(2026, 8, 25, 12);
  JaxEvent event(
    String id,
    EventStatus status, {
    String? parent,
    String? categoryId,
  }) => JaxEvent(
    id: id,
    name: id,
    status: status,
    parentEventId: parent,
    categoryId: categoryId,
    createdAt: time,
    updatedAt: time,
  );

  test('sets moves and clears the single parent relationship', () async {
    final repository = MemoryRepository([
      event('a', EventStatus.pending),
      event('b', EventStatus.pending),
      event('child', EventStatus.pending),
    ]);
    final update = UpdateEventParent(repository: repository, now: () => time);

    await update('child', 'a');
    expect((await repository.getEvent('child'))?.parentEventId, 'a');
    await update('child', 'b');
    expect((await repository.getEvent('child'))?.parentEventId, 'b');
    await update('child', null);
    expect((await repository.getEvent('child'))?.parentEventId, isNull);
  });

  test('rejects self cycle and assigning a descendant as parent', () async {
    final repository = MemoryRepository([
      event('a', EventStatus.pending),
      event('b', EventStatus.pending, parent: 'a'),
      event('c', EventStatus.pending, parent: 'b'),
    ]);
    final update = UpdateEventParent(repository: repository, now: () => time);

    await expectLater(update('a', 'a'), throwsA(isA<DomainFailure>()));
    await expectLater(update('a', 'c'), throwsA(isA<DomainFailure>()));
    expect((await repository.getEvent('a'))?.parentEventId, isNull);
  });

  test(
    'candidate and mutation scope use the effective root Category',
    () async {
      final repository = MemoryRepository([
        event('dev-root', EventStatus.pending, categoryId: 'dev'),
        event('dev-child', EventStatus.pending, parent: 'dev-root'),
        event('dev-peer', EventStatus.pending, categoryId: 'dev'),
        event('research-root', EventStatus.pending, categoryId: 'research'),
        event('research-child', EventStatus.pending, parent: 'research-root'),
        event('loose-root', EventStatus.pending),
        event('loose-child', EventStatus.pending, parent: 'loose-root'),
      ]);
      final service = EventHierarchyService(repository);
      final update = UpdateEventParent(repository: repository, now: () => time);

      expect(
        (await service.parentCandidates('dev-child')).map((event) => event.id),
        containsAll(['dev-root', 'dev-peer']),
      );
      expect(
        (await service.parentCandidates('dev-child')).map((event) => event.id),
        isNot(contains(anyOf('research-root', 'research-child'))),
      );
      expect(
        (await service.parentCandidates('research-child'))
            .map((event) => event.id),
        isNot(contains(anyOf('loose-root', 'loose-child'))),
      );
      await expectLater(
        update('dev-child', 'research-root'),
        throwsA(
          isA<DomainFailure>().having(
            (failure) => failure.message,
            'message',
            '只能在同一分类内调整事件层级',
          ),
        ),
      );
    },
  );

  test('candidate ranges respect status and remove cycle candidates', () async {
    final repository = MemoryRepository([
      event('pending', EventStatus.pending),
      event('paused', EventStatus.paused),
      event('completed', EventStatus.completed),
      event('descendant', EventStatus.pending, parent: 'pending'),
    ]);
    final service = EventHierarchyService(repository);

    expect(
      (await service.parentCandidates('pending')).map((e) => e.id),
      contains('paused'),
    );
    expect(
      (await service.parentCandidates('pending')).map((e) => e.id),
      isNot(contains('completed')),
    );
    expect(
      (await service.parentCandidates('pending')).map((e) => e.id),
      isNot(contains('descendant')),
    );
    expect(
      (await service.parentCandidates('completed')).map((e) => e.id),
      containsAll(['pending', 'paused']),
    );
    expect(
      (await service.childCandidates('completed')).map((e) => e.id),
      isNot(contains('pending')),
    );
    expect(
      (await service.childCandidates('pending')).map((e) => e.id),
      contains('completed'),
    );
  });

  test('events with direct children cannot be deleted', () async {
    final pendingRepository = MemoryRepository([
      event('parent', EventStatus.pending),
      event('child', EventStatus.pending, parent: 'parent'),
    ]);
    await expectLater(
      DeleteEvent(pendingRepository)('parent'),
      throwsA(isA<DomainFailure>()),
    );

    final historyRepository = MemoryRepository([
      event('parent', EventStatus.completed),
      event('child', EventStatus.completed, parent: 'parent'),
    ]);
    await expectLater(
      DeleteHistoryRecord(historyRepository)('parent'),
      throwsA(isA<DomainFailure>()),
    );
  });
}
