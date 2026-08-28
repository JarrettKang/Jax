import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/execution_time_segment.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/routine.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';

void main() {
  test(
    'SQLite mutates Event and Routine closed segments without changing owners',
    () async {
      final db = await AppDatabase.inMemory();
      addTearDown(db.close);
      final repo = SqliteEventRepository(db);
      final now = DateTime.utc(2026, 8, 28, 12);
      await repo.insertEvent(
        JaxEvent(
          id: 'e',
          name: 'Event',
          status: EventStatus.completed,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await repo.insertRoutine(
        Routine(
          id: 'r',
          name: 'Routine',
          recurrence: RoutineRecurrence.daily,
          weekdayMask: 0,
          isActive: true,
          sortOrder: 0,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await db.database.insert('routine_executions', {
        'id': 'rx',
        'routine_id': 'r',
        'occurrence_date': '2026-08-28',
        'status': 'completed',
        'created_at_utc': now.millisecondsSinceEpoch,
        'updated_at_utc': now.millisecondsSinceEpoch,
      });
      final eventSegment = ExecutionTimeSegment(
        id: 'es',
        ownerType: ExecutionOwnerType.event,
        ownerId: 'e',
        ownerName: 'Event',
        startedAt: DateTime.utc(2026, 8, 28, 9),
        endedAt: DateTime.utc(2026, 8, 28, 10),
        createdAt: now,
      );
      final routineSegment = ExecutionTimeSegment(
        id: 'rs',
        ownerType: ExecutionOwnerType.routine,
        ownerId: 'rx',
        ownerName: 'Routine',
        startedAt: DateTime.utc(2026, 8, 28, 10),
        endedAt: DateTime.utc(2026, 8, 28, 11),
        createdAt: now,
      );
      await repo.insertExecutionTimeSegment(eventSegment);
      await repo.insertExecutionTimeSegment(routineSegment);
      expect(await repo.getAllExecutionTimeSegments(), hasLength(2));
      await repo.updateExecutionTimeSegment(
        ExecutionTimeSegment(
          id: 'es',
          ownerType: ExecutionOwnerType.event,
          ownerId: 'e',
          ownerName: 'Event',
          startedAt: DateTime.utc(2026, 8, 28, 9, 10),
          endedAt: DateTime.utc(2026, 8, 28, 9, 40),
          createdAt: now,
        ),
      );
      await repo.deleteExecutionTimeSegment(ExecutionOwnerType.routine, 'rs');
      expect(
        (await repo.getRunSegments('e')).single.endedAt,
        DateTime.utc(2026, 8, 28, 9, 40),
      );
      expect(await repo.getRoutineRunSegments('rx'), isEmpty);
      expect((await repo.getEvent('e'))!.status, EventStatus.completed);
      expect(
        (await repo.getRoutineExecutions()).single.status,
        RoutineExecutionStatus.completed,
      );
    },
  );

  test(
    'SQLite closes a running segment and owner in one transaction',
    () async {
      final db = await AppDatabase.inMemory();
      addTearDown(db.close);
      final repo = SqliteEventRepository(db);
      final now = DateTime.utc(2026, 8, 28, 12);
      await repo.insertEvent(
        JaxEvent(
          id: 'running',
          name: 'Running',
          status: EventStatus.running,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await db.database.insert('run_segments', {
        'id': 'open',
        'event_id': 'running',
        'started_at_utc': DateTime.utc(2026, 8, 28, 9).millisecondsSinceEpoch,
        'ended_at_utc': null,
        'created_at_utc': now.millisecondsSinceEpoch,
      });
      final actualEnd = DateTime.utc(2026, 8, 28, 10, 20);
      await repo.finishRunningAt(
        ownerType: ExecutionOwnerType.event,
        ownerId: 'running',
        segmentId: 'open',
        endedAt: actualEnd,
        complete: false,
      );
      expect((await repo.getEvent('running'))!.status, EventStatus.paused);
      expect((await repo.getRunSegments('running')).single.endedAt, actualEnd);
    },
  );
}
