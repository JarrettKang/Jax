import '../../core/entities/jax_day.dart';
import '../../core/entities/routine.dart';
import '../../core/services/temporal_routine.dart';

class TodayTemporalEntry {
  const TodayTemporalEntry(
    this.routine,
    this.window,
    this.execution,
    this.state,
  );
  final Routine routine;
  final ResolvedTemporalWindow window;
  final RoutineExecution? execution;
  final TemporalRecommendationState state;
  String get identity => 'routine-${routine.id}@${window.occurrenceKey}';
}

/// Ephemeral view over original occurrences; no copies or persisted agenda order.
class TodayTemporalView {
  const TodayTemporalView(this.now, this.later, this.nextBoundary);
  final List<TodayTemporalEntry> now, later;
  final DateTime? nextBoundary;
  static TodayTemporalView derive({
    required List<Routine> routines,
    required JaxDay day,
    required DateTime time,
    required RoutineExecution? Function(Routine, String) executionFor,
    String? runningRoutineId,
    Set<String> waitingRoutineIds = const {},
  }) {
    final entries = <TodayTemporalEntry>[];
    final boundaries = <DateTime>[if (day.end.isAfter(time)) day.end];
    for (final routine in routines) {
      if (waitingRoutineIds.contains(routine.id)) continue;
      for (final window in TemporalRoutine.windows(routine, day)) {
        final execution = executionFor(routine, window.occurrenceKey);
        if (execution?.status == RoutineExecutionStatus.completed ||
            execution?.status == RoutineExecutionStatus.waiting) {
          continue;
        }
        final state = window.stateAt(time);
        entries.add(TodayTemporalEntry(routine, window, execution, state));
        for (final boundary in [
          window.startDateTime,
          window.idealEndDateTime.add(const Duration(milliseconds: 1)),
          window.latestEndDateTime.add(const Duration(milliseconds: 1)),
        ]) {
          if (boundary.isAfter(time)) boundaries.add(boundary);
        }
      }
    }
    final activeIds = {
      ?runningRoutineId,
      for (final entry in entries)
        if (entry.window.recommendsAt(time)) entry.routine.id,
    };
    final now = entries
        .where(
          (e) =>
              e.window.recommendsAt(time) &&
              e.execution?.status != RoutineExecutionStatus.running &&
              e.routine.id != runningRoutineId,
        )
        .toList();
    final later = entries
        .where(
          (e) =>
              e.state == TemporalRecommendationState.inactive &&
              !activeIds.contains(e.routine.id) &&
              e.window.startDateTime.isBefore(day.end),
        )
        .toList();
    int stable(TodayTemporalEntry a, TodayTemporalEntry b) {
      final order = a.routine.sortOrder.compareTo(b.routine.sortOrder);
      return order != 0 ? order : a.identity.compareTo(b.identity);
    }

    now.sort((a, b) {
      for (final comparison in [
        a.window.latestEndDateTime.compareTo(b.window.latestEndDateTime),
        a.window.idealEndDateTime.compareTo(b.window.idealEndDateTime),
        a.window.startDateTime.compareTo(b.window.startDateTime),
      ]) {
        if (comparison != 0) return comparison;
      }
      return stable(a, b);
    });
    later.sort((a, b) {
      final c = a.window.startDateTime.compareTo(b.window.startDateTime);
      return c != 0 ? c : stable(a, b);
    });
    boundaries.sort();
    return TodayTemporalView(now, later, boundaries.firstOrNull);
  }
}
