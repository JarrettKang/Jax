import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/run_segment.dart';
import 'package:jax/core/errors/domain_failure.dart';
import 'package:jax/core/use_cases/complete_event.dart';

import '../support/memory_repository.dart';

void main() {
  test(
    'completes running event and excludes paused time from duration',
    () async {
      final start = DateTime.utc(2026);
      final end = start.add(const Duration(minutes: 30));
      final event = JaxEvent(
        id: 'one',
        name: '任务',
        status: EventStatus.running,
        createdAt: start,
        updatedAt: start,
        firstStartedAt: start,
      );
      final repository = MemoryRepository([event])
        ..segments.addAll([
          RunSegment(
            id: 'old',
            eventId: 'one',
            startedAt: start,
            endedAt: start.add(const Duration(minutes: 10)),
            createdAt: start,
          ),
          RunSegment(
            id: 'open',
            eventId: 'one',
            startedAt: start.add(const Duration(minutes: 20)),
            createdAt: start,
          ),
        ]);
      final record = await CompleteEvent(
        repository: repository,
        now: () => end,
      )('one');
      expect(record.event.status, EventStatus.completed);
      expect(record.event.completedAt, end);
      expect(record.duration, const Duration(minutes: 20));
      expect(await repository.getIncompleteEvents(), isEmpty);
    },
  );

  test(
    'corrected completion closes the original open segment exactly once',
    () async {
      final start = DateTime.utc(2026, 8, 31, 10);
      final now = DateTime.utc(2026, 8, 31, 12, 30);
      final corrected = DateTime.utc(2026, 8, 31, 12);
      final repository =
          MemoryRepository([
              JaxEvent(
                id: 'event',
                name: '检查超算',
                status: EventStatus.running,
                createdAt: start,
                updatedAt: start,
                firstStartedAt: start,
              ),
            ])
            ..segments.add(
              RunSegment(
                id: 'open',
                eventId: 'event',
                startedAt: start,
                createdAt: start,
              ),
            );
      final complete = CompleteEvent(repository: repository, now: () => now);
      await complete('event', endTime: corrected);
      expect(repository.events.single.status, EventStatus.completed);
      expect(repository.events.single.completedAt, corrected);
      expect(repository.segments, hasLength(1));
      expect(repository.segments.single.id, 'open');
      expect(repository.segments.single.endedAt, corrected);
    },
  );

  test('corrected completion rejects end before start and after now', () async {
    final start = DateTime.utc(2026, 8, 31, 10);
    final now = DateTime.utc(2026, 8, 31, 12, 30);
    MemoryRepository repository() =>
        MemoryRepository([
            JaxEvent(
              id: 'event',
              name: 'event',
              status: EventStatus.running,
              createdAt: start,
              updatedAt: start,
              firstStartedAt: start,
            ),
          ])
          ..segments.add(
            RunSegment(
              id: 'open',
              eventId: 'event',
              startedAt: start,
              createdAt: start,
            ),
          );
    for (final invalid in [start, now.add(const Duration(seconds: 1))]) {
      final repo = repository();
      await expectLater(
        CompleteEvent(repository: repo, now: () => now)(
          'event',
          endTime: invalid,
        ),
        throwsA(isA<DomainFailure>()),
      );
      expect(repo.events.single.status, EventStatus.running);
      expect(repo.segments.single.endedAt, isNull);
    }
  });
}
