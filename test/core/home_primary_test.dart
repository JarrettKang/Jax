import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/routine.dart';
import 'package:jax/ui/controllers/event_controller.dart';
import 'package:jax/ui/controllers/home_view_state.dart';

import '../support/memory_repository.dart';

void main() {
  test('primary uses resolved latest, ideal, start; all existing executions take precedence', () async {
    final now = DateTime(2026, 9, 15, 12);
    final repo = MemoryRepository();
    Routine r(String id, int end, int latest, int start) => Routine(
      id: id,
      name: id,
      recurrence: RoutineRecurrence.daily,
      weekdayMask: 0,
      isActive: true,
      sortOrder: 0,
      createdAt: now,
      updatedAt: now,
      timeRecommendation: RoutineTimeRecommendation(
        startMinute: start,
        endMinute: end,
        latestEndMinute: latest,
      ),
    );
    repo.routines.addAll([
      r('late', 780, 960, 600),
      r('active', 780, 840, 600),
      r('overdue', 690, 840, 600),
      r('earlierStart', 690, 840, 540),
    ]);
    final c = EventController(
      repository: repo,
      newId: () => 'unused',
      now: () => now,
    );
    addTearDown(c.dispose);
    await c.load();
    expect(homePrimaryRecommendation(c)!.routine.id, 'earlierStart');
    for (final status in [
      RoutineExecutionStatus.paused,
      RoutineExecutionStatus.waiting,
      RoutineExecutionStatus.completed,
      RoutineExecutionStatus.running,
    ]) {
      repo.routineExecutions.clear();
      repo.routineExecutions.add(
        RoutineExecution(
          id: 'existing',
          routineId: 'earlierStart',
          occurrenceDate: '2026-09-15',
          status: status,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await c.load();
      expect(homePrimaryRecommendation(c)!.routine.id, 'overdue');
    }
  });
  test('cross-day primary starts and completes original occurrence', () async {
    final now = DateTime(2026, 9, 15, 0, 45);
    final repo = MemoryRepository();
    var id = 0;
    repo.routines.add(
      Routine(
        id: 'night',
        name: 'night',
        recurrence: RoutineRecurrence.daily,
        weekdayMask: 0,
        isActive: true,
        sortOrder: 0,
        createdAt: now,
        updatedAt: now,
        timeRecommendation: const RoutineTimeRecommendation(
          startMinute: 1350,
          endMinute: 30,
          latestEndMinute: 120,
        ),
      ),
    );
    final c = EventController(
      repository: repo,
      newId: () => 'id-${id++}',
      now: () => now,
    );
    addTearDown(c.dispose);
    await c.load();
    final entry = homePrimaryRecommendation(c)!;
    expect(entry.window.occurrenceKey, '2026-09-14');
    expect(
      await c.startRoutineOccurrence(entry.routine, entry.window.occurrenceKey),
      isNull,
    );
    expect(repo.routineExecutions.single.occurrenceDate, '2026-09-14');
    expect(homePrimaryRecommendation(c), isNull);
  });
}
