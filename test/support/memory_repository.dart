import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/run_segment.dart';
import 'package:jax/core/entities/category.dart';
import 'package:jax/core/entities/event_day_plan.dart';
import 'package:jax/core/entities/routine.dart';
import 'package:jax/core/entities/routine_category.dart';
import 'package:jax/core/repositories/event_repository.dart';
import 'package:jax/core/repositories/event_day_plan_repository.dart';
import 'package:jax/core/repositories/routine_repository.dart';
import 'package:jax/core/errors/domain_failure.dart';

class MemoryRepository
    implements EventRepository, EventDayPlanRepository, RoutineRepository {
  MemoryRepository([
    Iterable<JaxEvent> seed = const [],
    this.autoPlanSeedEvents = true,
  ]) : events = List.of(seed);
  final bool autoPlanSeedEvents;
  final List<JaxEvent> events;
  final List<RunSegment> segments = [];
  final List<Category> categories = [];
  final List<Routine> routines = [];
  final List<RoutineCategory> routineCategories = [];
  final List<RoutineExecution> routineExecutions = [];
  final List<RoutineRunSegment> routineSegments = [];
  final List<EventDayPlan> eventDayPlans = [];
  @override
  Future<void> insertEvent(JaxEvent event) async => events.add(event);

  @override
  Future<List<JaxEvent>> getIncompleteEvents() async =>
      events.where((event) => event.status.name != 'completed').toList();
  @override
  Future<List<JaxEvent>> getCompletedEvents() async =>
      events.where((event) => event.status.name == 'completed').toList();
  @override
  Future<JaxEvent?> getEvent(String id) async =>
      events.where((event) => event.id == id).firstOrNull;
  @override
  Future<void> updateEvent(JaxEvent event) async =>
      events[events.indexWhere((item) => item.id == event.id)] = event;
  @override
  Future<void> startEvent(JaxEvent event, RunSegment segment) async {
    await pauseRunningRoutine(event.updatedAt);
    await updateEvent(event);
    segments.add(segment);
  }

  @override
  Future<List<RunSegment>> getRunSegments(String eventId) async =>
      segments.where((segment) => segment.eventId == eventId).toList();
  @override
  Future<List<RunSegment>> getAllRunSegments() async => List.of(segments);
  @override
  Future<void> insertHistoricalRunSegment(RunSegment segment) async =>
      segments.add(segment);
  @override
  Future<void> updateClosedRunSegment(RunSegment segment) async {
    final index = segments.indexWhere(
      (s) => s.id == segment.id && s.endedAt != null,
    );
    if (index < 0) throw StateError('Closed run segment not found');
    segments[index] = segment;
  }

  @override
  Future<void> adjustRunningEventStart({
    required String eventId,
    required String segmentId,
    required DateTime expectedStartedAt,
    required DateTime newStartedAt,
    required DateTime updatedAt,
  }) async {
    _validateCorrection(newStartedAt, expectedStartedAt, updatedAt);
    final runningEvents = events
        .where((event) => event.status == EventStatus.running)
        .toList();
    final runningRoutines = routineExecutions
        .where(
          (execution) => execution.status == RoutineExecutionStatus.running,
        )
        .toList();
    final open = segments
        .where(
          (segment) => segment.eventId == eventId && segment.endedAt == null,
        )
        .toList();
    final allOpenEvents = segments.where((segment) => segment.endedAt == null);
    final allOpenRoutines = routineSegments.where(
      (segment) => segment.endedAt == null,
    );
    if (runningEvents.length != 1 ||
        runningEvents.single.id != eventId ||
        runningRoutines.isNotEmpty ||
        open.length != 1 ||
        allOpenEvents.length != 1 ||
        allOpenEvents.single.id != segmentId ||
        allOpenRoutines.isNotEmpty ||
        open.single.id != segmentId ||
        open.single.startedAt.toUtc() != expectedStartedAt.toUtc()) {
      throw const DomainFailure('当前执行状态已发生变化，请重新操作');
    }
    _validateMemoryOverlap(
      newStartedAt,
      updatedAt,
      exceptEventSegmentId: segmentId,
    );
    if (newStartedAt.toUtc() != expectedStartedAt.toUtc()) {
      segments[segments.indexOf(open.single)] = open.single.copyWith(
        startedAt: newStartedAt.toUtc(),
      );
    }
  }

  @override
  Future<void> deleteClosedRunSegment(String id) async {
    final index = segments.indexWhere((s) => s.id == id && s.endedAt != null);
    if (index < 0) throw StateError('Closed run segment not found');
    segments.removeAt(index);
  }

  @override
  Future<void> pauseEvent(JaxEvent event, RunSegment segment) async {
    await updateEvent(event);
    segments[segments.indexWhere((item) => item.id == segment.id)] = segment;
  }

  @override
  Future<void> restoreCompletedEvents(List<JaxEvent> restored) async {
    for (final event in restored) {
      final current = await getEvent(event.id);
      if (current == null || current.status.name != 'completed') {
        throw StateError('Invalid completed Event restoration');
      }
    }
    for (final event in restored) {
      await updateEvent(event);
    }
  }

  @override
  Future<void> switchRunningEvent({
    required JaxEvent pausedRunning,
    required RunSegment closedSegment,
    required JaxEvent runningTarget,
    required RunSegment newSegment,
  }) async {
    await updateEvent(pausedRunning);
    segments[segments.indexWhere((item) => item.id == closedSegment.id)] =
        closedSegment;
    await updateEvent(runningTarget);
    segments.add(newSegment);
  }

  @override
  Future<void> deleteEvent(String id) async {
    events.removeWhere((event) => event.id == id);
    segments.removeWhere((segment) => segment.eventId == id);
    eventDayPlans.removeWhere((plan) => plan.eventId == id);
  }

  @override
  Future<List<Category>> getCategories() async => _orderedCategories();
  List<Category> _orderedCategories() =>
      categories.toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  @override
  Future<void> insertCategory(Category category) async =>
      categories.add(category);
  @override
  Future<void> updateCategory(Category category) async =>
      categories[categories.indexWhere((item) => item.id == category.id)] =
          category;
  @override
  Future<void> deleteCategory(String id) async {
    categories.removeWhere((item) => item.id == id);
    for (var i = 0; i < categories.length; i++) {
      categories[i] = categories[i].copyWith(sortOrder: i);
    }
    for (var i = 0; i < events.length; i++) {
      if (events[i].categoryId == id) {
        events[i] = events[i].copyWith(categoryId: null);
      }
    }
  }

  @override
  Future<void> reorderCategory(String id, int targetIndex) async {
    final ordered = _orderedCategories();
    final current = ordered.indexWhere((item) => item.id == id);
    if (current < 0 || targetIndex < 0 || targetIndex >= ordered.length) {
      throw StateError('Invalid category order');
    }
    final moved = ordered.removeAt(current);
    ordered.insert(targetIndex, moved);
    for (var i = 0; i < ordered.length; i++) {
      categories[categories.indexWhere((item) => item.id == ordered[i].id)] =
          ordered[i].copyWith(sortOrder: i);
    }
  }

  @override
  Future<void> setStandaloneCategory(String eventId, String? categoryId) async {
    final event = await getEvent(eventId);
    if (event == null) throw StateError('Event not found: $eventId');
    if (event.sourcePlanItemId != null) {
      throw StateError('Planned Event cannot own a direct Category');
    }
    if (categoryId != null &&
        !categories.any((item) => item.id == categoryId)) {
      throw StateError('Category not found');
    }
    await updateEvent(event.copyWith(categoryId: categoryId));
  }

  @override
  Future<String?> getEffectiveCategoryId(String eventId) async {
    final event = await getEvent(eventId);
    if (event == null) throw StateError('Event not found: $eventId');
    return event.categoryId;
  }

  @override
  Future<List<EventDayPlan>> getEventDayPlans(String dayKey) async {
    final explicit = eventDayPlans.where((p) => p.dayKey == dayKey).toList();
    final result = explicit.isEmpty && autoPlanSeedEvents
        ? [
            for (var i = 0; i < events.length; i++)
              EventDayPlan(
                eventId: events[i].id,
                dayKey: dayKey,
                order: i,
                createdAt: events[i].createdAt,
              ),
          ]
        : explicit;
    return result..sort((a, b) => a.order.compareTo(b.order));
  }

  @override
  Future<void> addEventDayPlan(EventDayPlan plan) async {
    if (!eventDayPlans.any(
      (p) => p.eventId == plan.eventId && p.dayKey == plan.dayKey,
    )) {
      eventDayPlans.add(plan);
    }
  }

  @override
  Future<void> addEventDayPlans(List<EventDayPlan> plans) async {
    for (final plan in plans) {
      await addEventDayPlan(plan);
    }
  }

  @override
  Future<void> removeEventDayPlan(String eventId, String dayKey) async =>
      eventDayPlans.removeWhere(
        (p) => p.eventId == eventId && p.dayKey == dayKey,
      );
  @override
  Future<void> reorderEventDayPlan(
    String eventId,
    String dayKey,
    int targetIndex,
  ) async {
    final plans = await getEventDayPlans(dayKey);
    final current = plans.indexWhere((p) => p.eventId == eventId);
    if (current < 0 || targetIndex < 0 || targetIndex >= plans.length) {
      throw StateError('Invalid Today order');
    }
    final moved = plans.removeAt(current);
    plans.insert(targetIndex, moved);
    for (var i = 0; i < plans.length; i++) {
      final index = eventDayPlans.indexWhere(
        (p) => p.eventId == plans[i].eventId && p.dayKey == dayKey,
      );
      eventDayPlans[index] = plans[i].copyWith(order: i);
    }
  }

  @override
  Future<List<Routine>> getRoutines() async => List.of(routines)
    ..sort((a, b) {
      final category = (a.routineCategoryId ?? '').compareTo(
        b.routineCategoryId ?? '',
      );
      return category != 0 ? category : a.sortOrder.compareTo(b.sortOrder);
    });
  @override
  Future<List<RoutineCategory>> getRoutineCategories() async =>
      List.of(routineCategories)
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  @override
  Future<void> insertRoutineCategory(RoutineCategory c) async =>
      routineCategories.add(c);
  @override
  Future<void> updateRoutineCategory(RoutineCategory c) async =>
      routineCategories[routineCategories.indexWhere((x) => x.id == c.id)] = c;
  @override
  Future<void> reorderRoutineCategory(String id, int targetIndex) async {
    final items = await getRoutineCategories();
    final current = items.indexWhere((c) => c.id == id);
    if (current < 0 || targetIndex < 0 || targetIndex >= items.length) return;
    final moved = items.removeAt(current);
    items.insert(targetIndex, moved);
    for (var i = 0; i < items.length; i++) {
      routineCategories[routineCategories.indexWhere(
        (c) => c.id == items[i].id,
      )] = items[i].copyWith(
        sortOrder: i,
      );
    }
  }

  @override
  Future<void> deleteRoutineCategory(String id) async {
    routineCategories.removeWhere((c) => c.id == id);
    var next =
        routines
            .where((r) => r.routineCategoryId == null)
            .fold<int>(
              -1,
              (value, r) => r.sortOrder > value ? r.sortOrder : value,
            ) +
        1;
    for (var i = 0; i < routines.length; i++) {
      if (routines[i].routineCategoryId == id) {
        routines[i] = routines[i].copyWith(
          clearCategory: true,
          sortOrder: next++,
        );
      }
    }
  }

  @override
  Future<void> insertRoutine(Routine r) async {
    if (routines.any((x) => x.id == r.id)) throw StateError('duplicate');
    routines.add(r);
  }

  @override
  Future<void> updateRoutine(Routine r) async =>
      routines[routines.indexWhere((x) => x.id == r.id)] = r;
  @override
  Future<void> reorderRoutine(String id, int targetIndex) async {
    final source = routines.firstWhere((r) => r.id == id);
    final ordered = (await getRoutines())
        .where((r) => r.routineCategoryId == source.routineCategoryId)
        .toList();
    final current = ordered.indexWhere((r) => r.id == id);
    if (current < 0 || targetIndex < 0 || targetIndex >= ordered.length) {
      throw StateError('Invalid Routine order');
    }
    final moved = ordered.removeAt(current);
    ordered.insert(targetIndex, moved);
    for (var i = 0; i < ordered.length; i++) {
      routines[routines.indexWhere((r) => r.id == ordered[i].id)] = ordered[i]
          .copyWith(sortOrder: i);
    }
  }

  @override
  Future<RoutineExecution?> getRoutineExecution(String id, String day) async =>
      routineExecutions
          .where((e) => e.routineId == id && e.occurrenceDate == day)
          .firstOrNull;
  @override
  Future<List<RoutineExecution>> getRoutineExecutions() async =>
      List.of(routineExecutions);
  @override
  Future<RoutineExecution?> getRunningRoutineExecution() async =>
      routineExecutions
          .where((e) => e.status == RoutineExecutionStatus.running)
          .firstOrNull;
  @override
  Future<RoutineExecution?> getUnfinishedRoutineExecution(String id) async =>
      routineExecutions
          .where(
            (e) =>
                e.routineId == id &&
                e.status != RoutineExecutionStatus.completed,
          )
          .firstOrNull;
  @override
  Future<List<RoutineRunSegment>> getRoutineRunSegments(String id) async =>
      routineSegments.where((s) => s.executionId == id).toList();
  @override
  Future<List<RoutineRunSegment>> getAllRoutineRunSegments() async =>
      List.of(routineSegments);
  @override
  Future<void> insertHistoricalRoutineExecution(
    RoutineExecution e,
    RoutineRunSegment s,
  ) async {
    if (!routineExecutions.any((item) => item.id == e.id)) {
      routineExecutions.add(e);
    }
    routineSegments.add(s);
  }

  @override
  Future<void> updateClosedRoutineRunSegment(RoutineRunSegment s) async {
    final index = routineSegments.indexWhere(
      (item) => item.id == s.id && item.endedAt != null,
    );
    if (index < 0) throw StateError('Closed routine segment not found');
    routineSegments[index] = s;
  }

  @override
  Future<void> adjustRunningRoutineStart({
    required String executionId,
    required String segmentId,
    required DateTime expectedStartedAt,
    required DateTime newStartedAt,
    required DateTime updatedAt,
  }) async {
    _validateCorrection(newStartedAt, expectedStartedAt, updatedAt);
    final runningEvents = events
        .where((event) => event.status == EventStatus.running)
        .toList();
    final runningRoutines = routineExecutions
        .where(
          (execution) => execution.status == RoutineExecutionStatus.running,
        )
        .toList();
    final open = routineSegments
        .where(
          (segment) =>
              segment.executionId == executionId && segment.endedAt == null,
        )
        .toList();
    final allOpenEvents = segments.where((segment) => segment.endedAt == null);
    final allOpenRoutines = routineSegments.where(
      (segment) => segment.endedAt == null,
    );
    if (runningEvents.isNotEmpty ||
        runningRoutines.length != 1 ||
        runningRoutines.single.id != executionId ||
        open.length != 1 ||
        allOpenEvents.isNotEmpty ||
        allOpenRoutines.length != 1 ||
        allOpenRoutines.single.id != segmentId ||
        open.single.id != segmentId ||
        open.single.startedAt.toUtc() != expectedStartedAt.toUtc()) {
      throw const DomainFailure('当前执行状态已发生变化，请重新操作');
    }
    _validateMemoryOverlap(
      newStartedAt,
      updatedAt,
      exceptRoutineSegmentId: segmentId,
    );
    if (newStartedAt.toUtc() != expectedStartedAt.toUtc()) {
      routineSegments[routineSegments.indexOf(open.single)] = open.single
          .copyWith(startedAt: newStartedAt.toUtc());
    }
  }

  @override
  Future<void> deleteClosedRoutineRunSegment(String id) async {
    final index = routineSegments.indexWhere(
      (item) => item.id == id && item.endedAt != null,
    );
    if (index < 0) throw StateError('Closed routine segment not found');
    routineSegments.removeAt(index);
  }

  @override
  Future<void> startRoutineExecution(
    RoutineExecution e,
    RoutineRunSegment s,
    DateTime now,
  ) async {
    final running = events.where((x) => x.status.name == 'running').firstOrNull;
    if (running != null) {
      final open = segments
          .where((x) => x.eventId == running.id && x.endedAt == null)
          .firstOrNull;
      await updateEvent(
        running.copyWith(status: EventStatus.paused, updatedAt: now),
      );
      if (open != null) {
        segments[segments.indexOf(open)] = open.copyWith(endedAt: now);
      }
    }
    await pauseRunningRoutine(now);
    final i = routineExecutions.indexWhere((x) => x.id == e.id);
    if (i < 0) {
      routineExecutions.add(e);
    } else {
      routineExecutions[i] = e;
    }
    routineSegments.add(s);
  }

  @override
  Future<void> pauseRoutineExecution(
    RoutineExecution e,
    RoutineRunSegment s,
  ) async {
    await updateRoutineExecutionOnly(e);
    routineSegments[routineSegments.indexWhere((x) => x.id == s.id)] = s;
  }

  @override
  Future<void> completeRoutineExecution(
    RoutineExecution e,
    RoutineRunSegment s,
  ) => pauseRoutineExecution(e, s);
  @override
  Future<void> updateRoutineExecutionOnly(RoutineExecution e) async {
    routineExecutions[routineExecutions.indexWhere((x) => x.id == e.id)] = e;
  }

  @override
  Future<void> pauseRunningRoutine(DateTime now) async {
    final e = routineExecutions
        .where((x) => x.status == RoutineExecutionStatus.running)
        .firstOrNull;
    if (e == null) return;
    final s = routineSegments
        .where((x) => x.executionId == e.id && x.endedAt == null)
        .firstOrNull;
    await updateRoutineExecutionOnly(
      e.copyWith(status: RoutineExecutionStatus.paused, updatedAt: now),
    );
    if (s != null) {
      routineSegments[routineSegments.indexOf(s)] = s.copyWith(endedAt: now);
    }
  }

  void _validateCorrection(DateTime value, DateTime current, DateTime now) {
    if (value.isAfter(now)) {
      throw const DomainFailure('开始时间不能晚于当前时间');
    }
    if (value.isAfter(current)) {
      throw const DomainFailure('开始时间只能向前修正。如需修改已记录时间，请在记录中编辑');
    }
  }

  void _validateMemoryOverlap(
    DateTime start,
    DateTime end, {
    String? exceptEventSegmentId,
    String? exceptRoutineSegmentId,
  }) {
    final ranges = <({String id, bool routine, DateTime start, DateTime? end})>[
      for (final segment in segments)
        (
          id: segment.id,
          routine: false,
          start: segment.startedAt,
          end: segment.endedAt,
        ),
      for (final segment in routineSegments)
        (
          id: segment.id,
          routine: true,
          start: segment.startedAt,
          end: segment.endedAt,
        ),
    ];
    for (final range in ranges) {
      if ((!range.routine && range.id == exceptEventSegmentId) ||
          (range.routine && range.id == exceptRoutineSegmentId)) {
        continue;
      }
      final otherEnd = range.end ?? end;
      if (start.isBefore(otherEnd) && end.isAfter(range.start)) {
        throw const DomainFailure('执行时间与已有记录重叠');
      }
    }
  }
}
