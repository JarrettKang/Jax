import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/routine.dart';
import 'package:jax/core/entities/run_segment.dart';
import 'package:jax/core/services/routine_service.dart';

import '../support/memory_repository.dart';

void main() {
  test('recurrence applies to local calendar weekdays', () {
    Routine r(RoutineRecurrence type, int mask) => Routine(
      id: 'r',
      name: 'R',
      recurrence: type,
      weekdayMask: mask,
      isActive: true,
      sortOrder: 0,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    final monday = DateTime(2026, 8, 24);
    expect(
      List.generate(
        7,
        (i) => r(
          RoutineRecurrence.daily,
          0,
        ).appliesTo(monday.add(Duration(days: i))),
      ),
      everyElement(true),
    );
    expect(
      List.generate(
        7,
        (i) => r(
          RoutineRecurrence.weekdays,
          0,
        ).appliesTo(monday.add(Duration(days: i))),
      ),
      [true, true, true, true, true, false, false],
    );
    expect(
      List.generate(
        7,
        (i) => r(
          RoutineRecurrence.weekends,
          0,
        ).appliesTo(monday.add(Duration(days: i))),
      ),
      [false, false, false, false, false, true, true],
    );
    expect(
      List.generate(
        7,
        (i) => r(
          RoutineRecurrence.selectedWeekdays,
          (1 << 1) | (1 << 3),
        ).appliesTo(monday.add(Duration(days: i))),
      ),
      [false, true, false, true, false, false, false],
    );
  });
  test('routine occurrence is unique and next day is unstarted', () async {
    final repo = MemoryRepository();
    var id = 0;
    final service = RoutineService(
      repository: repo,
      newId: () => '${id++}',
      now: () => DateTime(2026, 8, 27, 8),
    );
    await service.create('洗漱', null, RoutineRecurrence.daily, 0);
    final r = repo.routines.single;
    await service.start(r);
    final e = repo.routineExecutions.single;
    await service.complete(e);
    expect(
      (await repo.getRoutineExecution(r.id, '2026-08-27'))?.status,
      RoutineExecutionStatus.completed,
    );
    expect(await repo.getRoutineExecution(r.id, '2026-08-28'), isNull);
    expect(repo.events, isEmpty);
  });
  test('event and routine share one running slot in both directions', () async {
    final t = DateTime.utc(2026, 8, 27, 8);
    final event = JaxEvent(
      id: 'e',
      name: 'Event',
      status: EventStatus.running,
      firstStartedAt: t,
      createdAt: t,
      updatedAt: t,
    );
    final repo = MemoryRepository([event]);
    repo.segments.add(
      RunSegment(id: 'es', eventId: 'e', startedAt: t, createdAt: t),
    );
    var id = 0;
    final service = RoutineService(
      repository: repo,
      newId: () => 'r${id++}',
      now: () => t.add(const Duration(minutes: 5)),
    );
    await service.create('洗澡', null, RoutineRecurrence.daily, 0);
    await service.start(repo.routines.single);
    expect(repo.events.single.status, EventStatus.paused);
    expect(
      repo.routineExecutions.single.status,
      RoutineExecutionStatus.running,
    );
    final next = event.copyWith(
      status: EventStatus.running,
      updatedAt: t.add(const Duration(minutes: 10)),
    );
    await repo.startEvent(
      next,
      RunSegment(
        id: 'next',
        eventId: 'e',
        startedAt: t.add(const Duration(minutes: 10)),
        createdAt: t,
      ),
    );
    expect(repo.routineExecutions.single.status, RoutineExecutionStatus.paused);
    expect(repo.events.single.status, EventStatus.running);
  });
  test(
    'inactive hides occurrences but preserves history and can reactivate',
    () async {
      final repo = MemoryRepository();
      var id = 0;
      final s = RoutineService(
        repository: repo,
        newId: () => '${id++}',
        now: () => DateTime(2026, 8, 27),
      );
      await s.create('整理', null, RoutineRecurrence.daily, 0);
      final r = repo.routines.single;
      await s.start(r);
      await s.setActive(r, false);
      expect(repo.routines.single.isActive, isFalse);
      expect(repo.routineExecutions, hasLength(1));
      await s.setActive(repo.routines.single, true);
      expect(repo.routines.single.isActive, isTrue);
    },
  );
}
