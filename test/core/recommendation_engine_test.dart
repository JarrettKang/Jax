import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_day.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/routine.dart';
import 'package:jax/core/recommendation/recommendation_engine.dart';

void main() {
  const provider = HomeCandidateProvider();
  const engine = RecommendationEngine(rules: [TimeRecommendationRule()]);
  final created = DateTime.utc(2026, 9, 1);

  Routine routine(
    String id, {
    int start = 11 * 60,
    int end = 13 * 60,
    String? reason,
    RoutineType type = RoutineType.scheduled,
    RoutineRecurrence recurrence = RoutineRecurrence.daily,
    int mask = 0,
  }) => Routine(
    id: id,
    name: id,
    type: type,
    recurrence: recurrence,
    weekdayMask: mask,
    isActive: true,
    sortOrder: 0,
    createdAt: created,
    updatedAt: created,
    timeRecommendation: type == RoutineType.scheduled
        ? RoutineTimeRecommendation(
            startMinute: start,
            endMinute: end,
            reason: reason,
          )
        : null,
  );

  RoutineExecution execution(String id, RoutineExecutionStatus status) =>
      RoutineExecution(
        id: 'execution-$id',
        routineId: id,
        occurrenceDate: '2026-09-03',
        status: status,
        createdAt: created,
        updatedAt: created,
      );

  RecommendationContext context(
    DateTime now,
    List<Routine> routines, {
    List<JaxEvent> events = const [],
    Map<String, RoutineExecution?> executions = const {},
    String? runningRoutineId,
    String? runningEventId,
  }) => RecommendationContext(
    currentLocalDateTime: now,
    currentJaxDay: JaxDay.containing(now),
    todayEvents: events,
    todayScheduledRoutines: routines,
    routineExecutions: executions,
    runningRoutineId: runningRoutineId,
    runningEventId: runningEventId,
  );

  Recommendation? resultAt(
    Routine value,
    int hour,
    int minute, {
    RoutineExecution? currentExecution,
  }) {
    final c = context(
      DateTime(2026, 9, 3, hour, minute),
      [value],
      executions: {value.id: currentExecution},
    );
    return engine.recommend(c, provider.provide(c)).firstOrNull;
  }

  test('ordinary window uses inclusive start and exclusive end', () {
    final lunch = routine('lunch');
    expect(resultAt(lunch, 10, 59)?.strength, RecommendationStrength.normal);
    expect(resultAt(lunch, 11, 0)?.strength, RecommendationStrength.promoted);
    expect(resultAt(lunch, 12, 59)?.strength, RecommendationStrength.promoted);
    expect(resultAt(lunch, 13, 0)?.strength, RecommendationStrength.normal);
  });

  test('cross-midnight window follows local wall clock', () {
    final sleep = routine('sleep', start: 23 * 60 + 30, end: 90);
    expect(resultAt(sleep, 23, 29)?.strength, RecommendationStrength.normal);
    expect(resultAt(sleep, 23, 30)?.strength, RecommendationStrength.promoted);
    expect(resultAt(sleep, 0, 30)?.strength, RecommendationStrength.promoted);
    expect(resultAt(sleep, 1, 29)?.strength, RecommendationStrength.promoted);
    expect(resultAt(sleep, 1, 30)?.strength, RecommendationStrength.normal);
  });

  test('custom and default reasons are derived', () {
    expect(resultAt(routine('lunch', reason: '该吃午饭了'), 12, 0)?.reason, '该吃午饭了');
    expect(resultAt(routine('default'), 12, 0)?.reason, '当前处于推荐时间 11:00–13:00');
  });

  test('recurrence miss, completed, and running do not promote', () {
    final thursday = routine(
      'wednesday',
      recurrence: RoutineRecurrence.selectedWeekdays,
      mask: 1 << 2,
    );
    expect(resultAt(thursday, 12, 0)?.strength, RecommendationStrength.normal);
    final done = routine('done');
    expect(
      resultAt(
        done,
        12,
        0,
        currentExecution: execution(done.id, RoutineExecutionStatus.completed),
      ),
      isNull,
    );
    final running = routine('running');
    final c = context(
      DateTime(2026, 9, 3, 12),
      [running],
      executions: {
        running.id: execution(running.id, RoutineExecutionStatus.running),
      },
      runningRoutineId: running.id,
    );
    expect(provider.provide(c), isEmpty);
  });

  test('paused routine promotes and multiple matches keep stable order', () {
    final first = routine('first');
    final second = routine('second');
    final c = context(
      DateTime(2026, 9, 3, 12),
      [first, second],
      executions: {
        first.id: execution(first.id, RoutineExecutionStatus.paused),
      },
    );
    final results = engine.recommend(c, provider.provide(c));
    expect(results.map((value) => value.candidate.id), ['first', 'second']);
    expect(
      results.map((value) => value.strength),
      everyElement(RecommendationStrength.promoted),
    );
  });

  test(
    'one promoted plus normal candidates ranks deterministically for top 3',
    () {
      JaxEvent event(String id) => JaxEvent(
        id: id,
        name: id,
        status: EventStatus.pending,
        createdAt: created,
        updatedAt: created,
      );
      final promoted = routine('promoted');
      final normal = routine('normal', start: 14 * 60, end: 15 * 60);
      final c = context(
        DateTime(2026, 9, 3, 12),
        [promoted, normal],
        events: [event('e1'), event('e2'), event('e3')],
      );
      final results = engine.recommend(c, provider.provide(c));
      expect(results.take(3).map((value) => value.candidate.id), [
        'promoted',
        'e1',
        'e2',
      ]);
      expect(
        results
            .where(
              (value) =>
                  value.candidate.kind == RecommendationCandidateKind.event,
            )
            .map((value) => value.signals),
        everyElement(isEmpty),
      );
    },
  );

  test(
    'without a match the existing Event then Routine order is unchanged',
    () {
      final event = JaxEvent(
        id: 'event',
        name: 'event',
        status: EventStatus.pending,
        createdAt: created,
        updatedAt: created,
      );
      final normal = routine('routine', start: 14 * 60, end: 15 * 60);
      final c = context(DateTime(2026, 9, 3, 12), [normal], events: [event]);
      expect(
        engine.recommend(c, provider.provide(c)).map((r) => r.candidate.id),
        ['event', 'routine'],
      );
    },
  );
}
