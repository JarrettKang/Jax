enum RoutineRecurrence { daily, weekdays, weekends, selectedWeekdays }

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
    this.categoryId,
  });
  final String id, name;
  final String? categoryId;
  final RoutineRecurrence recurrence;
  final int weekdayMask, sortOrder;
  final bool isActive;
  final DateTime createdAt, updatedAt;
  bool appliesTo(DateTime date) => switch (recurrence) {
    RoutineRecurrence.daily => true,
    RoutineRecurrence.weekdays => date.weekday <= 5,
    RoutineRecurrence.weekends => date.weekday >= 6,
    RoutineRecurrence.selectedWeekdays =>
      weekdayMask & (1 << (date.weekday - 1)) != 0,
  };
  Routine copyWith({
    String? name,
    String? categoryId,
    bool clearCategory = false,
    RoutineRecurrence? recurrence,
    int? weekdayMask,
    bool? isActive,
    int? sortOrder,
    DateTime? updatedAt,
  }) => Routine(
    id: id,
    name: name ?? this.name,
    categoryId: clearCategory ? null : categoryId ?? this.categoryId,
    recurrence: recurrence ?? this.recurrence,
    weekdayMask: weekdayMask ?? this.weekdayMask,
    isActive: isActive ?? this.isActive,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

enum RoutineExecutionStatus { running, paused, completed }

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
  RoutineRunSegment copyWith({DateTime? endedAt}) => RoutineRunSegment(
    id: id,
    executionId: executionId,
    startedAt: startedAt,
    createdAt: createdAt,
    endedAt: endedAt ?? this.endedAt,
  );
  Duration durationAt(DateTime now) =>
      (endedAt ?? now.toUtc()).difference(startedAt);
}
