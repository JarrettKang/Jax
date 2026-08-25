import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/errors/domain_failure.dart';
import 'package:jax/core/use_cases/complete_event.dart';

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
    completedAt: status == EventStatus.completed ? time : null,
  );

  test('unfinished direct child prevents parent completion', () async {
    final repository = MemoryRepository([
      event('parent', EventStatus.paused),
      event('child', EventStatus.pending, parent: 'parent'),
    ]);

    await expectLater(
      CompleteEvent(repository: repository, now: () => time)('parent'),
      throwsA(isA<DomainFailure>()),
    );
    expect((await repository.getEvent('parent'))?.status, EventStatus.paused);
  });

  for (final status in [EventStatus.pending, EventStatus.paused]) {
    test('all completed children allow $status parent completion', () async {
      final repository = MemoryRepository([
        event('parent', status),
        event('first', EventStatus.completed, parent: 'parent'),
        event('second', EventStatus.completed, parent: 'parent'),
      ]);

      await CompleteEvent(repository: repository, now: () => time)('parent');
      final parent = await repository.getEvent('parent');
      expect(parent?.status, EventStatus.completed);
      expect(parent?.firstStartedAt, isNull);
      expect(await repository.getRunSegments('parent'), isEmpty);
    });
  }

  test('leaf pending event still cannot complete directly', () async {
    final repository = MemoryRepository([event('leaf', EventStatus.pending)]);
    await expectLater(
      CompleteEvent(repository: repository, now: () => time)('leaf'),
      throwsA(isA<DomainFailure>()),
    );
  });
}
