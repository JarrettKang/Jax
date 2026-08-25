import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/run_segment.dart';
import 'package:jax/core/errors/domain_failure.dart';
import 'package:jax/core/use_cases/start_event.dart';
import 'package:jax/core/use_cases/resume_event.dart';

import '../support/memory_repository.dart';

void main() {
  final start = DateTime.utc(2026, 8, 25, 10);
  JaxEvent event(String id, EventStatus status, {String? parent}) => JaxEvent(
    id: id,
    name: id,
    status: status,
    parentEventId: parent,
    firstStartedAt: status == EventStatus.running ? start : null,
    createdAt: start,
    updatedAt: start,
  );

  test('running ancestor atomically switches to pending descendant', () async {
    final repository =
        MemoryRepository([
            event('root', EventStatus.running),
            event('middle', EventStatus.pending, parent: 'root'),
            event('leaf', EventStatus.pending, parent: 'middle'),
          ])
          ..segments.add(
            RunSegment(
              id: 'open',
              eventId: 'root',
              startedAt: start,
              createdAt: start,
            ),
          );
    final now = start.add(const Duration(minutes: 5));

    await StartEvent(
      repository: repository,
      newId: () => 'leaf-open',
      now: () => now,
    )('leaf');

    expect((await repository.getEvent('root'))?.status, EventStatus.paused);
    expect((await repository.getEvent('middle'))?.status, EventStatus.paused);
    expect((await repository.getEvent('leaf'))?.status, EventStatus.running);
    expect(repository.segments.first.endedAt, now);
    expect(repository.segments.last.eventId, 'leaf');
  });

  test('running event still blocks unrelated event', () async {
    final repository =
        MemoryRepository([
            event('running', EventStatus.running),
            event('unrelated', EventStatus.pending),
          ])
          ..segments.add(
            RunSegment(
              id: 'open',
              eventId: 'running',
              startedAt: start,
              createdAt: start,
            ),
          );

    var generatedIds = 0;
    await expectLater(
      StartEvent(
        repository: repository,
        newId: () {
          generatedIds++;
          return 'new';
        },
        now: () => start,
      )('unrelated'),
      throwsA(isA<DomainFailure>()),
    );
    expect(generatedIds, 0);
  });

  test('running ancestor atomically switches to paused descendant', () async {
    final repository =
        MemoryRepository([
            event('root', EventStatus.running),
            event('leaf', EventStatus.paused, parent: 'root').copyWith(
              firstStartedAt: start.subtract(const Duration(minutes: 2)),
            ),
          ])
          ..segments.add(
            RunSegment(
              id: 'root-open',
              eventId: 'root',
              startedAt: start,
              createdAt: start,
            ),
          );
    final now = start.add(const Duration(minutes: 3));

    await ResumeEvent(
      repository: repository,
      newId: () => 'leaf-open',
      now: () => now,
    )('leaf');

    expect((await repository.getEvent('root'))?.status, EventStatus.paused);
    expect((await repository.getEvent('leaf'))?.status, EventStatus.running);
    expect(repository.segments.first.endedAt, now);
    expect(repository.segments.last.eventId, 'leaf');
  });

  test('switching to descendant pauses every unfinished ancestor', () async {
    final repository =
        MemoryRepository([
            event('top', EventStatus.pending),
            event('running', EventStatus.running, parent: 'top'),
            event('leaf', EventStatus.pending, parent: 'running'),
          ])
          ..segments.add(
            RunSegment(
              id: 'open',
              eventId: 'running',
              startedAt: start,
              createdAt: start,
            ),
          );

    await StartEvent(
      repository: repository,
      newId: () => 'leaf-open',
      now: () => start.add(const Duration(minutes: 1)),
    )('leaf');

    expect((await repository.getEvent('top'))?.status, EventStatus.paused);
    expect((await repository.getEvent('running'))?.status, EventStatus.paused);
    expect((await repository.getEvent('leaf'))?.status, EventStatus.running);
  });

  test('running descendant still blocks starting its ancestor', () async {
    final repository =
        MemoryRepository([
            event('root', EventStatus.pending),
            event('leaf', EventStatus.running, parent: 'root'),
          ])
          ..segments.add(
            RunSegment(
              id: 'open',
              eventId: 'leaf',
              startedAt: start,
              createdAt: start,
            ),
          );

    await expectLater(
      StartEvent(repository: repository, newId: () => 'new', now: () => start)(
        'root',
      ),
      throwsA(isA<DomainFailure>()),
    );
  });
}
