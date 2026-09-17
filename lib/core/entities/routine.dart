enum RoutineRecurrence { daily, weekdays, weekends, selectedWeekdays }

enum RoutineType { scheduled, onDemand }

class RoutineTimeRecommendation {
  const RoutineTimeRecommendation({
    required this.startMinute,
    required this.endMinute,
    this.reason,
    int? latestEndMinute,
  }) : latestEndMinute = latestEndMinute ?? endMinute;

  final int startMinute;
  final int endMinute;
  final int latestEndMinute;
  int get recommendStartTime => startMinute;
  int get idealEndTime => endMinute;
  int get latestEndTime => latestEndMinute;
  final String? reason;
}

const _unchangedTimeRecommendation = Object();

class Routine {
  const Routine({
    required this.id,
    required this.name,
    required this.recurrence,
    required this.weekdayMask,
    required this.isActive,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
    this.routineCategoryId,
    this.type = RoutineType.scheduled,
    this.timeRecommendation,
    this.showInHomeQuickActions = false,
  });
  final String id, name;
  final String? routineCategoryId;
  final RoutineType type;
  final RoutineRecurrence recurrence;
  final RoutineTimeRecommendation? timeRecommendation;
  final int weekdayMask, sortOrder;
  final bool isActive;
  final bool showInHomeQuickActions;
  bool get isHomeQuickAction =>
      isActive && !isScheduled && showInHomeQuickActions;
  final DateTime createdAt, updatedAt;
  bool appliesTo(DateTime date) => switch (recurrence) {
    RoutineRecurrence.daily => true,
    RoutineRecurrence.weekdays => date.weekday <= 5,
    RoutineRecurrence.weekends => date.weekday >= 6,
    RoutineRecurrence.selectedWeekdays =>
      weekdayMask & (1 << (date.weekday - 1)) != 0,
  };
  bool get isScheduled => type == RoutineType.scheduled;
  Routine copyWith({
    String? name,
    String? routineCategoryId,
    bool clearCategory = false,
    RoutineRecurrence? recurrence,
    int? weekdayMask,
    bool? isActive,
    bool? showInHomeQuickActions,
    int? sortOrder,
    DateTime? updatedAt,
    RoutineType? type,
    Object? timeRecommendation = _unchangedTimeRecommendation,
  }) => Routine(
    id: id,
    name: name ?? this.name,
    routineCategoryId: clearCategory
        ? null
        : routineCategoryId ?? this.routineCategoryId,
    recurrence: recurrence ?? this.recurrence,
    type: type ?? this.type,
    timeRecommendation:
        identical(timeRecommendation, _unchangedTimeRecommendation)
        ? this.timeRecommendation
        : timeRecommendation as RoutineTimeRecommendation?,
    weekdayMask: weekdayMask ?? this.weekdayMask,
    isActive: isActive ?? this.isActive,
    showInHomeQuickActions:
        showInHomeQuickActions ?? this.showInHomeQuickActions,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

enum RoutineExecutionStatus { running, paused, completed, waiting }

class RoutineExecution {
  const RoutineExecution({
    required this.id,
    required this.routineId,
    required this.occurrenceDate,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
  });
  final String id, routineId, occurrenceDate;
  final RoutineExecutionStatus status;
  final DateTime createdAt, updatedAt;
  final DateTime? completedAt;
  RoutineExecution copyWith({
    RoutineExecutionStatus? status,
    DateTime? updatedAt,
    DateTime? completedAt,
  }) => RoutineExecution(
    id: id,
    routineId: routineId,
    occurrenceDate: occurrenceDate,
    status: status ?? this.status,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    completedAt: completedAt ?? this.completedAt,
  );
}

class RoutineRunSegment {
  const RoutineRunSegment({
    required this.id,
    required this.executionId,
    required this.startedAt,
    required this.createdAt,
    this.endedAt,
  });
  final String id, executionId;
  final DateTime startedAt, createdAt;
  final DateTime? endedAt;
  RoutineRunSegment copyWith({DateTime? startedAt, DateTime? endedAt}) =>
      RoutineRunSegment(
        id: id,
        executionId: executionId,
        startedAt: startedAt ?? this.startedAt,
        createdAt: createdAt,
        endedAt: endedAt ?? this.endedAt,
      );
  Duration durationAt(DateTime now) =>
      (endedAt ?? now.toUtc()).difference(startedAt);
}
