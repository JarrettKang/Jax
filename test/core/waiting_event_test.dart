import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/run_segment.dart';
import 'package:jax/core/use_cases/complete_event.dart';
import 'package:jax/core/use_cases/pause_event.dart';
import 'package:jax/core/use_cases/resume_event.dart';
import 'package:jax/core/use_cases/wait_event.dart';

import '../support/memory_repository.dart';

void main() {
  final start = DateTime.utc(2026, 8, 26, 10);
  JaxEvent event(String id, EventStatus status) => JaxEvent(
    id: id,
    name: id,
    status: status,
    createdAt: start,
    updatedAt: start,
    firstStartedAt: status == EventStatus.pending ? null : start,
  );

  test(
    'running -> waiting closes segment and waiting -> running opens one',
    () async {
      final repository = MemoryRepository([event('a', EventStatus.running)])
        ..segments.add(
          RunSegment(
            id: 'first',
            eventId: 'a',
            startedAt: start,
            createdAt: start,
          ),
        );
      final waitedAt = start.add(const Duration(minutes: 5));
      await WaitEvent(repository: repository, now: () => waitedAt)('a');
      expect((await repository.getEvent('a'))!.status, EventStatus.waiting);
      expect(repository.segments.single.endedAt, waitedAt);

      final resumedAt = waitedAt.add(const Duration(minutes: 20));
      await ResumeEvent(
        repository: repository,
        newId: () => 'second',
        now: () => resumedAt,
      )('a');
      expect((await repository.getEvent('a'))!.status, EventStatus.running);
      expect(repository.segments, hasLength(2));
      expect(repository.segments.last.startedAt, resumedAt);
    },
  );

  test('paused -> waiting and waiting -> paused create no segments', () async {
    final repository = MemoryRepository([event('a', EventStatus.paused)]);
    await WaitEvent(repository: repository, now: () => start)('a');
    await PauseEvent(repository: repository, now: () => start)('a');
    expect((await repository.getEvent('a'))!.status, EventStatus.paused);
    expect(repository.segments, isEmpty);
  });

  test('waiting can complete directly', () async {
    final repository = MemoryRepository([event('a', EventStatus.waiting)]);
    await CompleteEvent(repository: repository, now: () => start)('a');
    expect((await repository.getEvent('a'))!.status, EventStatus.completed);
  });

  test('multiple waiting do not consume the single running slot', () async {
    final repository =
        MemoryRepository([
            event('a', EventStatus.waiting),
            event('b', EventStatus.waiting),
            event('c', EventStatus.running),
          ])
          ..segments.add(
            RunSegment(
              id: 'c-segment',
              eventId: 'c',
              startedAt: start,
              createdAt: start,
            ),
          );
    expect(
      (await repository.getIncompleteEvents()).where(
        (item) => item.status == EventStatus.waiting,
      ),
      hasLength(2),
    );
    expect(
      (await repository.getIncompleteEvents()).where(
        (item) => item.status == EventStatus.running,
      ),
      hasLength(1),
    );
  });
}
