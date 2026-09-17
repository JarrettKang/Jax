import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/jax_day.dart';
import 'package:jax/core/entities/routine.dart';
import 'package:jax/core/services/temporal_routine.dart';
import 'package:jax/core/recommendation/recommendation_engine.dart';

Routine temporal({
  RoutineRecurrence recurrence = RoutineRecurrence.daily,
  int mask = 0,
}) => Routine(
  id: 'night',
  name: 'Night',
  recurrence: recurrence,
  weekdayMask: mask,
  isActive: true,
  sortOrder: 0,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  timeRecommendation: const RoutineTimeRecommendation(
    startMinute: 1350,
    endMinute: 30,
    latestEndMinute: 120,
  ),
);
void main() {
  final day = JaxDay.forDisplayDate(DateTime(2026, 9, 14));
  const lunch = RoutineTimeRecommendation(
    startMinute: 660,
    endMinute: 780,
    latestEndMinute: 1020,
  );
  for (final entry in [
    (10, 59, 0, TemporalRecommendationState.inactive),
    (11, 0, 0, TemporalRecommendationState.active),
    (12, 0, 0, TemporalRecommendationState.active),
    (13, 0, 0, TemporalRecommendationState.active),
    (13, 1, 0, TemporalRecommendationState.overdue),
    (16, 59, 0, TemporalRecommendationState.overdue),
    (17, 0, 0, TemporalRecommendationState.overdue),
    (17, 0, 1, TemporalRecommendationState.expired),
  ]) {
    test(
      'lunch boundary $entry',
      () => expect(
        TemporalRoutine.resolve(
          lunch,
          day,
        ).stateAt(DateTime(2026, 9, 14, entry.$1, entry.$2, entry.$3)),
        entry.$4,
      ),
    );
  }
  final night = temporal();
  for (final entry in [
    (14, 22, 0, TemporalRecommendationState.inactive),
    (14, 22, 30, TemporalRecommendationState.active),
    (14, 23, 30, TemporalRecommendationState.active),
    (15, 0, 30, TemporalRecommendationState.active),
    (15, 1, 0, TemporalRecommendationState.overdue),
    (15, 2, 0, TemporalRecommendationState.overdue),
    (15, 2, 1, TemporalRecommendationState.expired),
  ]) {
    test('night boundary $entry keeps original occurrence', () {
      final window = TemporalRoutine.resolve(night.timeRecommendation!, day);
      expect(
        window.stateAt(DateTime(2026, 9, entry.$1, entry.$2, entry.$3)),
        entry.$4,
      );
      expect(window.occurrenceKey, '2026-09-14');
      expect(window.latestEndDateTime, DateTime(2026, 9, 15, 2));
    });
  }
  test('23:00 rollover retains old active and new inactive windows', () {
    final now = DateTime(2026, 9, 14, 23, 30);
    final windows = TemporalRoutine.windows(night, JaxDay.containing(now));
    expect(windows.map((w) => w.occurrenceKey), ['2026-09-14', '2026-09-15']);
    expect(windows.map((w) => w.stateAt(now)), [
      TemporalRecommendationState.active,
      TemporalRecommendationState.inactive,
    ]);
    expect(TemporalRoutine.occurrenceKey(night, now), '2026-09-14');
    expect(TemporalRoutine.occurrenceKey(night, now.toUtc()), '2026-09-14');
  });
  test('23:30 start belongs to following display date', () {
    final window = TemporalRoutine.resolve(
      const RoutineTimeRecommendation(
        startMinute: 1410,
        endMinute: 30,
        latestEndMinute: 120,
      ),
      day,
    );
    expect(window.startDateTime, DateTime(2026, 9, 13, 23, 30));
    expect(window.idealEndDateTime, DateTime(2026, 9, 14, 0, 30));
  });
  test('invalid order and partial/full-day ambiguity rejected; ideal equals latest allowed', () {
    for (final c in [
      const RoutineTimeRecommendation(
        startMinute: 660,
        endMinute: 1080,
        latestEndMinute: 840,
      ),
      const RoutineTimeRecommendation(
        startMinute: 660,
        endMinute: 660,
        latestEndMinute: 900,
      ),
      const RoutineTimeRecommendation(
        startMinute: 660,
        endMinute: 780,
        latestEndMinute: 1440,
      ),
    ]) {
      expect(() => TemporalRoutine.validate(c), throwsA(anything));
    }
    TemporalRoutine.validate(
      const RoutineTimeRecommendation(
        startMinute: 660,
        endMinute: 780,
        latestEndMinute: 780,
      ),
    );
  });
  test(
    'Monday occurrence still recommends Tuesday; completion excludes it',
    () {
      final routine = temporal(
        recurrence: RoutineRecurrence.selectedWeekdays,
        mask: 1,
      );
      final now = DateTime(2026, 9, 15, 0, 45);
      RecommendationContext context(RoutineExecution? e) =>
          RecommendationContext(
            currentLocalDateTime: now,
            currentJaxDay: JaxDay.containing(now),
            todayEvents: [],
            todayScheduledRoutines: [routine],
            routineExecutions: {routine.id: e},
          );
      final c = context(null);
      expect(const HomeCandidateProvider().provide(c), hasLength(1));
      expect(
        const TimeRecommendationRule().evaluate(
          c,
          const HomeCandidateProvider().provide(c).single,
        ),
        isNotNull,
      );
      final done = RoutineExecution(
        id: 'done',
        routineId: routine.id,
        occurrenceDate: '2026-09-14',
        status: RoutineExecutionStatus.completed,
        createdAt: now,
        updatedAt: now,
      );
      expect(const HomeCandidateProvider().provide(context(done)), isEmpty);
      final next = DateTime(2026, 9, 16, 0, 45);
      expect(
        TemporalRoutine.actionable(routine, JaxDay.containing(next), next),
        isNull,
      );
    },
  );
}
