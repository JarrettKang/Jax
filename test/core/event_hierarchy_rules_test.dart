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
  JaxEvent event(String id, EventStatus status, {String? parent}) => JaxEvent(
    id: id,
    name: id,
    status: status,
    parentEventId: parent,
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
