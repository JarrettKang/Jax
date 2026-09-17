import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/routine.dart';
import 'package:jax/core/entities/jax_day.dart';
import 'package:jax/core/services/temporal_routine.dart';
import 'package:jax/ui/controllers/today_temporal_view.dart';

Routine routine(
  String id,
  int start,
  int ideal,
  int latest, {
  int order = 0,
  int mask = 0,
}) => Routine(
  id: id,
  name: id,
  recurrence: mask == 0
      ? RoutineRecurrence.daily
      : RoutineRecurrence.selectedWeekdays,
  weekdayMask: mask,
  isActive: true,
  sortOrder: order,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  timeRecommendation: RoutineTimeRecommendation(
    startMinute: start,
    endMinute: ideal,
    latestEndMinute: latest,
  ),
);
void main() {
  TodayTemporalView view(
    DateTime now,
    List<Routine> routines, {
    Set<String> done = const {},
  }) => TodayTemporalView.derive(
    routines: routines,
    day: JaxDay.containing(now),
    time: now,
    executionFor: (r, key) => done.contains('${r.id}@$key')
        ? RoutineExecution(
            id: 'done',
            routineId: r.id,
            occurrenceDate: key,
            status: RoutineExecutionStatus.completed,
            createdAt: now,
            updatedAt: now,
          )
        : null,
  );
  final lunch = routine('lunch', 660, 780, 1020);
  for (final entry in [
    (10, 59, 0, 1),
    (11, 0, 1, 0),
    (13, 1, 1, 0),
    (17, 1, 0, 0),
  ]) {
    test('lifecycle partitions $entry', () {
      final v = view(DateTime(2026, 9, 14, entry.$1, entry.$2), [lunch]);
      expect(v.now.length, entry.$3);
      expect(v.later.length, entry.$4);
    });
  }
  test('completed, inactive routine and recurrence miss excluded', () {
    final now = DateTime(2026, 9, 14, 12);
    expect(view(now, [lunch], done: {'lunch@2026-09-14'}).now, isEmpty);
    expect(view(now, [lunch.copyWith(isActive: false)]).now, isEmpty);
    expect(
      view(now, [routine('tuesday', 660, 780, 1020, mask: 2)]).now,
      isEmpty,
    );
  });
  test(
    'urgency sort uses latest then ideal then start and stable identity',
    () {
      final v = view(DateTime(2026, 9, 14, 12), [
        routine('last', 600, 780, 1080),
        routine('ideal-late', 600, 780, 1020),
        routine('start-late', 660, 720, 1020),
        routine('first', 600, 720, 1020),
      ]);
      expect(v.now.map((e) => e.routine.id), [
        'first',
        'start-late',
        'ideal-late',
        'last',
      ]);
    },
  );
  test('active and overdue sort together by latest', () {
    final v = view(DateTime(2026, 9, 14, 14), [
      routine('overdue', 660, 780, 1020),
      routine('active', 660, 900, 960),
    ]);
    expect(v.now.map((e) => e.routine.id), ['active', 'overdue']);
    expect(v.now.last.state, TemporalRecommendationState.overdue);
  });
  test('later sorted by start not routine order', () {
    final v = view(DateTime(2026, 9, 14, 12), [
      routine('night', 1350, 30, 120),
      routine('dinner', 1050, 1140, 1260, order: 5),
    ]);
    expect(v.later.map((e) => e.routine.id), ['dinner', 'night']);
  });
  test(
    'prior active suppresses later duplicate until completed or expired',
    () {
      final night = routine('night', 1350, 30, 120);
      for (final time in [
        DateTime(2026, 9, 14, 22, 30),
        DateTime(2026, 9, 14, 23, 30),
        DateTime(2026, 9, 15, 0, 45),
      ]) {
        final v = view(time, [night]);
        expect(v.now.single.window.occurrenceKey, '2026-09-14');
        expect(v.later, isEmpty);
      }
      final expired = view(DateTime(2026, 9, 15, 2, 1), [night]);
      expect(expired.now, isEmpty);
      expect(expired.later.single.window.occurrenceKey, '2026-09-15');
      final done = view(
        DateTime(2026, 9, 15, 0, 45),
        [night],
        done: {'night@2026-09-14'},
      );
      expect(done.now, isEmpty);
      expect(done.later, hasLength(1));
    },
  );
  test('next boundary includes exact inclusive endpoint transition', () {
    expect(
      view(DateTime(2026, 9, 14, 10, 59), [lunch]).nextBoundary,
      DateTime(2026, 9, 14, 11),
    );
    expect(
      view(DateTime(2026, 9, 14, 13), [lunch]).nextBoundary,
      DateTime(2026, 9, 14, 13).add(const Duration(milliseconds: 1)),
    );
    expect(
      view(DateTime(2026, 9, 14, 17), [lunch]).nextBoundary,
      DateTime(2026, 9, 14, 17).add(const Duration(milliseconds: 1)),
    );
  });
}
