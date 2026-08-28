import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/execution_time_segment.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/run_segment.dart';
import 'package:jax/core/entities/routine.dart';
import 'package:jax/core/services/execution_time_service.dart';
import 'package:jax/core/services/time_summary_service.dart';

import '../support/memory_repository.dart';

void main() {
  final now = DateTime.utc(2026, 8, 28, 12);
  JaxEvent event(String id, EventStatus status) => JaxEvent(
    id: id,
    name: id,
    status: status,
    createdAt: now,
    updatedAt: now,
  );
  test(
    'add edit delete preserve owner status and update summary facts',
    () async {
      final repo = MemoryRepository([event('done', EventStatus.completed)]);
      var n = 0;
      final service = ExecutionTimeService(
        repository: repo,
        newId: () => 's${n++}',
        now: () => now,
      );
      await service.add(
        type: ExecutionOwnerType.event,
        ownerId: 'done',
        ownerName: 'done',
        start: DateTime.utc(2026, 8, 28, 9),
        end: DateTime.utc(2026, 8, 28, 10),
      );
      var segment = (await service.segmentsFor(
        ExecutionOwnerType.event,
        'done',
      )).single;
      await service.edit(
        segment,
        DateTime.utc(2026, 8, 28, 9, 10),
        DateTime.utc(2026, 8, 28, 9, 50),
      );
      expect(
        (await repo.getRunSegments('done')).single.durationAt(now),
        const Duration(minutes: 40),
      );
      expect(repo.events.single.status, EventStatus.completed);
      expect(
        (await TimeSummaryService(repo, () => now).day(DateTime(2026, 8, 28)))
            .total,
        const Duration(minutes: 40),
      );
      segment = (await service.segmentsFor(
        ExecutionOwnerType.event,
        'done',
      )).single;
      await service.delete(segment);
      expect(await repo.getRunSegments('done'), isEmpty);
      expect(repo.events.single.status, EventStatus.completed);
    },
  );

  test(
    'cross-source overlap fails while adjacent and cross-23:00 are valid',
    () async {
      final repo = MemoryRepository([event('e', EventStatus.paused)])
        ..segments.add(
          RunSegment(
            id: 'existing',
            eventId: 'e',
            startedAt: DateTime.utc(2026, 8, 28, 10),
            endedAt: DateTime.utc(2026, 8, 28, 11),
            createdAt: now,
          ),
        )
        ..routines.add(
          Routine(
            id: 'r',
            name: '午饭',
            recurrence: RoutineRecurrence.daily,
            weekdayMask: 0,
            isActive: true,
            sortOrder: 0,
            createdAt: now,
            updatedAt: now,
          ),
        )
        ..routineExecutions.add(
          RoutineExecution(
            id: 'rx',
            routineId: 'r',
            occurrenceDate: '2026-08-28',
            status: RoutineExecutionStatus.completed,
            createdAt: now,
            updatedAt: now,
          ),
        );
      final service = ExecutionTimeService(
        repository: repo,
        newId: () => 'new',
        now: () => now,
      );
      expect(
        () => service.add(
          type: ExecutionOwnerType.routine,
          ownerId: 'rx',
          ownerName: '午饭',
          start: DateTime.utc(2026, 8, 28, 10, 30),
          end: DateTime.utc(2026, 8, 28, 11, 30),
        ),
        throwsA(isA<Exception>()),
      );
      await service.add(
        type: ExecutionOwnerType.routine,
        ownerId: 'rx',
        ownerName: '午饭',
        start: DateTime.utc(2026, 8, 28, 11),
        end: DateTime.utc(2026, 8, 28, 11, 30),
      );
      final lateNow = ExecutionTimeService(
        repository: repo,
        newId: () => 'cross',
        now: () => DateTime(2026, 8, 29),
      );
      await lateNow.add(
        type: ExecutionOwnerType.event,
        ownerId: 'e',
        ownerName: 'e',
        start: DateTime(2026, 8, 28, 22, 40),
        end: DateTime(2026, 8, 28, 23, 20),
      );
      final summary = TimeSummaryService(repo, () => DateTime(2026, 8, 29));
      expect(
        (await summary.day(DateTime(2026, 8, 28))).total,
        const Duration(hours: 1, minutes: 50),
      );
      expect(
        (await summary.day(DateTime(2026, 8, 29))).total,
        const Duration(minutes: 20),
      );
    },
  );

  test(
    'running can close at actual past time as paused or completed',
    () async {
      final repo = MemoryRepository([event('run', EventStatus.running)])
        ..segments.add(
          RunSegment(
            id: 'open',
            eventId: 'run',
            startedAt: DateTime.utc(2026, 8, 28, 10),
            createdAt: now,
          ),
        );
      final service = ExecutionTimeService(
        repository: repo,
        newId: () => 'x',
        now: () => now,
      );
      final open = (await service.segmentsFor(
        ExecutionOwnerType.event,
        'run',
      )).single;
      await service.finishRunning(
        open,
        DateTime.utc(2026, 8, 28, 11, 20),
        complete: false,
      );
      expect(repo.events.single.status, EventStatus.paused);
      expect(repo.segments.single.endedAt, DateTime.utc(2026, 8, 28, 11, 20));
    },
  );

  test(
    'completed Routine with no segment accepts history and keeps occurrence',
    () async {
      final repo = MemoryRepository()
        ..routines.add(
          Routine(
            id: 'r',
            name: '午饭',
            recurrence: RoutineRecurrence.daily,
            weekdayMask: 0,
            isActive: true,
            sortOrder: 0,
            createdAt: now,
            updatedAt: now,
          ),
        )
        ..routineExecutions.add(
          RoutineExecution(
            id: 'rx',
            routineId: 'r',
            occurrenceDate: '2026-08-28',
            status: RoutineExecutionStatus.completed,
            createdAt: now,
            updatedAt: now,
          ),
        );
      final service = ExecutionTimeService(
        repository: repo,
        newId: () => 'manual',
        now: () => now,
      );
      await service.add(
        type: ExecutionOwnerType.routine,
        ownerId: 'rx',
        ownerName: '午饭',
        start: DateTime.utc(2026, 8, 28, 11),
        end: DateTime.utc(2026, 8, 28, 11, 30),
      );
      expect(repo.routineExecutions.single.id, 'rx');
      expect(
        repo.routineExecutions.single.status,
        RoutineExecutionStatus.completed,
      );
      expect(
        repo.routineSegments.single.durationAt(now),
        const Duration(minutes: 30),
      );
    },
  );

  test(
    'current open segment participates in historical conflict checks',
    () async {
      final repo =
          MemoryRepository([
              event('running', EventStatus.running),
              event('past', EventStatus.paused),
            ])
            ..segments.add(
              RunSegment(
                id: 'open',
                eventId: 'running',
                startedAt: DateTime.utc(2026, 8, 28, 10),
                createdAt: now,
              ),
            );
      final service = ExecutionTimeService(
        repository: repo,
        newId: () => 'x',
        now: () => now,
      );
      expect(
        service.add(
          type: ExecutionOwnerType.event,
          ownerId: 'past',
          ownerName: 'past',
          start: DateTime.utc(2026, 8, 28, 11),
          end: DateTime.utc(2026, 8, 28, 11, 30),
        ),
        throwsA(isA<Exception>()),
      );
    },
  );

  test(
    'running Event completes at actual end when children are complete',
    () async {
      final parent = event('parent', EventStatus.running);
      final child = JaxEvent(
        id: 'child',
        name: 'child',
        status: EventStatus.completed,
        parentEventId: 'parent',
        createdAt: now,
        updatedAt: now,
      );
      final repo = MemoryRepository([parent, child])
        ..segments.add(
          RunSegment(
            id: 'open',
            eventId: 'parent',
            startedAt: DateTime.utc(2026, 8, 28, 10),
            createdAt: now,
          ),
        );
      final service = ExecutionTimeService(
        repository: repo,
        newId: () => 'x',
        now: () => now,
      );
      await service.finishRunning(
        (await service.segmentsFor(ExecutionOwnerType.event, 'parent')).single,
        DateTime.utc(2026, 8, 28, 11),
        complete: true,
      );
      expect(repo.events.first.status, EventStatus.completed);
      expect(repo.events.first.completedAt, DateTime.utc(2026, 8, 28, 11));
    },
  );

  test('actual-end completion preserves unfinished-child rule', () async {
    final parent = event('parent', EventStatus.running);
    final child = JaxEvent(
      id: 'child',
      name: 'child',
      status: EventStatus.pending,
      parentEventId: 'parent',
      createdAt: now,
      updatedAt: now,
    );
    final repo = MemoryRepository([parent, child])
      ..segments.add(
        RunSegment(
          id: 'open',
          eventId: 'parent',
          startedAt: DateTime.utc(2026, 8, 28, 10),
          createdAt: now,
        ),
      );
    final service = ExecutionTimeService(
      repository: repo,
      newId: () => 'x',
      now: () => now,
    );
    await expectLater(
      service.finishRunning(
        (await service.segmentsFor(ExecutionOwnerType.event, 'parent')).single,
        DateTime.utc(2026, 8, 28, 11),
        complete: true,
      ),
      throwsA(isA<Exception>()),
    );
    expect(repo.events.first.status, EventStatus.running);
    expect(repo.segments.single.endedAt, isNull);
  });
}
