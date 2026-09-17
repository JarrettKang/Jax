import '../entities/jax_day.dart';
import '../entities/routine.dart';
import '../errors/domain_failure.dart';

enum TemporalRecommendationState { inactive, active, overdue, expired }

class ResolvedTemporalWindow {
  const ResolvedTemporalWindow({
    required this.occurrenceDay,
    required this.startDateTime,
    required this.idealEndDateTime,
    required this.latestEndDateTime,
  });
  final JaxDay occurrenceDay;
  final DateTime startDateTime, idealEndDateTime, latestEndDateTime;
  String get occurrenceKey => occurrenceDay.key;
  TemporalRecommendationState stateAt(DateTime now) {
    if (now.isBefore(startDateTime)) {
      return TemporalRecommendationState.inactive;
    }
    if (!now.isAfter(idealEndDateTime)) {
      return TemporalRecommendationState.active;
    }
    if (!now.isAfter(latestEndDateTime)) {
      return TemporalRecommendationState.overdue;
    }
    return TemporalRecommendationState.expired;
  }

  bool recommendsAt(DateTime now) => switch (stateAt(now)) {
    TemporalRecommendationState.active ||
    TemporalRecommendationState.overdue => true,
    _ => false,
  };
}

/// The occurrence is anchored to the JaxDay containing its recommendation start.
/// Endpoints unwrap relative to that start, never relative to today's midnight.
class TemporalRoutine {
  static void validate(RoutineTimeRecommendation configuration) {
    final start = configuration.startMinute;
    final ideal = configuration.endMinute;
    final latest = configuration.latestEndMinute;
    if ([start, ideal, latest].any((m) => m < 0 || m >= 1440)) {
      throw const DomainFailure('推荐时间无效');
    }
    final idealOffset = (ideal - start + 1440) % 1440;
    final latestOffset = (latest - start + 1440) % 1440;
    if (idealOffset == 0 || idealOffset > latestOffset) {
      throw const DomainFailure('推荐时间顺序应为：开始推荐 → 理想完成前 → 最晚完成前（可跨午夜）');
    }
  }

  static ResolvedTemporalWindow resolve(
    RoutineTimeRecommendation configuration,
    JaxDay day,
  ) {
    validate(configuration);
    final minute = configuration.startMinute;
    final date = day.displayDate;
    // 23:xx is the evening preceding the JaxDay's display date.
    final start = DateTime(
      date.year,
      date.month,
      date.day - (minute >= 23 * 60 ? 1 : 0),
      minute ~/ 60,
      minute % 60,
    );
    DateTime endpoint(int value) => DateTime(
      start.year,
      start.month,
      start.day + (value < minute ? 1 : 0),
      value ~/ 60,
      value % 60,
    );
    return ResolvedTemporalWindow(
      occurrenceDay: day,
      startDateTime: start,
      idealEndDateTime: endpoint(configuration.endMinute),
      latestEndDateTime: endpoint(configuration.latestEndMinute),
    );
  }

  /// Includes the prior occurrence even when pending has no execution row yet.
  static List<ResolvedTemporalWindow> windows(Routine routine, JaxDay day) {
    if (!routine.isScheduled ||
        !routine.isActive ||
        routine.timeRecommendation == null) {
      return const [];
    }
    return [
      for (final owner in [day.previous, day])
        if (routine.appliesTo(owner.displayDate))
          resolve(routine.timeRecommendation!, owner),
    ];
  }

  static ResolvedTemporalWindow? actionable(
    Routine routine,
    JaxDay day,
    DateTime now,
  ) {
    for (final window in windows(routine, day)) {
      if (window.recommendsAt(now)) return window;
    }
    return null;
  }

  static String occurrenceKey(Routine routine, DateTime now) =>
      actionable(routine, JaxDay.containing(now), now)?.occurrenceKey ??
      JaxDay.containing(now).key;
}
