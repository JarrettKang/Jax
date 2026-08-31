import '../entities/daily_execution_segment.dart';
import '../entities/available_time_gap.dart';
import '../entities/event_status.dart';
import '../entities/jax_day.dart';
import '../entities/jax_event.dart';
import '../entities/run_segment.dart';
import '../entities/routine.dart';
import '../errors/domain_failure.dart';
import '../repositories/event_repository.dart';
import '../repositories/routine_repository.dart';

class ExecutionSegmentService {
  ExecutionSegmentService({
    required EventRepository repository,
    required this._now,
  }) : _events = repository,
       _routines = repository is RoutineRepository
           ? repository as RoutineRepository
           : null;
  final EventRepository _events;
  final RoutineRepository? _routines;
  final DateTime Function() _now;

  Future<List<DailyExecutionSegment>> forJaxDay(DateTime date) async {
    final day = JaxDay.forDisplayDate(date);
    final all = await _all();
    final now = _now().toLocal();
    return all.where((s) {
      final end = (s.endedAt ?? now).toLocal();
      return end.isAfter(day.start) && s.startedAt.toLocal().isBefore(day.end);
    }).toList()..sort((a, b) => a.startedAt.compareTo(b.startedAt));
  }

  Future<List<AvailableTimeGap>> availableGapsForJaxDay(DateTime date) async {
    final day = JaxDay.forDisplayDate(date);
    final now = _now().toLocal();
    if (!now.isAfter(day.start)) return const [];
    final windowEnd = now.isBefore(day.end) ? now : day.end;
    final occupied = <({DateTime start, DateTime end})>[];
    for (final segment in await _all()) {
      final rawStart = segment.startedAt.toLocal();
      final rawEnd = (segment.endedAt ?? now).toLocal();
      if (!rawEnd.isAfter(day.start) || !rawStart.isBefore(windowEnd)) {
        continue;
      }
      final start = rawStart.isBefore(day.start) ? day.start : rawStart;
      final end = rawEnd.isAfter(windowEnd) ? windowEnd : rawEnd;
      if (end.isAfter(start)) occupied.add((start: start, end: end));
    }
    occupied.sort((a, b) => a.start.compareTo(b.start));

    final gaps = <AvailableTimeGap>[];
    var cursor = day.start;
    for (final interval in occupied) {
      if (interval.start.isAfter(cursor)) {
        gaps.add(AvailableTimeGap(start: cursor, end: interval.start));
      }
      if (interval.end.isAfter(cursor)) cursor = interval.end;
    }
    if (windowEnd.isAfter(cursor)) {
      gaps.add(AvailableTimeGap(start: cursor, end: windowEnd));
    }
    return gaps;
  }

  Future<void> updateClosed(
    DailyExecutionSegment segment,
    DateTime start,
    DateTime end,
  ) async {
    _validateClosed(start, end);
    if (segment.isOpen) throw const DomainFailure('正在执行的记录不能在此编辑');
    await _validateOverlap(start, end, exceptId: segment.id);
    if (segment.source == ExecutionSource.event) {
      await _events.updateClosedRunSegment(
        RunSegment(
          id: segment.id,
          eventId: segment.ownerId,
          startedAt: start.toUtc(),
          endedAt: end.toUtc(),
          createdAt: segment.createdAt,
        ),
      );
    } else {
      await _routines!.updateClosedRoutineRunSegment(
        RoutineRunSegment(
          id: segment.id,
          executionId: segment.ownerId,
          startedAt: start.toUtc(),
          endedAt: end.toUtc(),
          createdAt: segment.createdAt,
        ),
      );
    }
  }

  Future<void> deleteClosed(DailyExecutionSegment segment) async {
    if (segment.isOpen) {
      throw const DomainFailure('正在执行的记录不能删除');
    }
    if (segment.source == ExecutionSource.event) {
      return _events.deleteClosedRunSegment(segment.id);
    }
    return _routines!.deleteClosedRoutineRunSegment(segment.id);
  }

  Future<void> validateCompletionEnd(
    String openSegmentId,
    DateTime start,
    DateTime end,
  ) async {
    _validateClosed(start, end);
    await _validateOverlap(start, end, exceptId: openSegmentId);
  }

  Future<void> validateNewRange(DateTime start, DateTime end) async {
    _validateClosed(start, end);
    await _validateOverlap(start, end);
  }

  Future<void> addEvent(
    String id,
    String segmentId,
    DateTime start,
    DateTime end,
  ) async {
    _validateClosed(start, end);
    final event = await _events.getEvent(id);
    if (event == null) throw const DomainFailure('事项不存在');
    if (event.status == EventStatus.running) {
      throw const DomainFailure('正在执行的对象不能补录');
    }
    await _validateOverlap(start, end);
    await _events.insertHistoricalRunSegment(
      RunSegment(
        id: segmentId,
        eventId: id,
        startedAt: start.toUtc(),
        endedAt: end.toUtc(),
        createdAt: _now().toUtc(),
      ),
    );
  }

  Future<void> addRoutine(
    String routineId,
    String executionId,
    String segmentId,
    String dayKey,
    DateTime start,
    DateTime end,
  ) async {
    final repo = _routines;
    if (repo == null) {
      throw const DomainFailure('日常不可用');
    }
    _validateClosed(start, end);
    await _validateOverlap(start, end);
    final routine = (await repo.getRoutines())
        .where((item) => item.id == routineId)
        .firstOrNull;
    if (routine == null) throw const DomainFailure('日常不存在');
    var execution = routine.isScheduled
        ? await repo.getRoutineExecution(routineId, dayKey)
        : await repo.getUnfinishedRoutineExecution(routineId);
    if (execution?.status == RoutineExecutionStatus.running) {
      throw const DomainFailure('正在执行的对象不能补录');
    }
    execution ??= RoutineExecution(
      id: executionId,
      routineId: routineId,
      occurrenceDate: dayKey,
      status: routine.isScheduled
          ? RoutineExecutionStatus.paused
          : RoutineExecutionStatus.completed,
      createdAt: _now().toUtc(),
      updatedAt: _now().toUtc(),
      completedAt: routine.isScheduled ? null : end.toUtc(),
    );
    await repo.insertHistoricalRoutineExecution(
      execution,
      RoutineRunSegment(
        id: segmentId,
        executionId: execution.id,
        startedAt: start.toUtc(),
        endedAt: end.toUtc(),
        createdAt: _now().toUtc(),
      ),
    );
  }

  void _validateClosed(DateTime start, DateTime end) {
    if (!end.isAfter(start)) {
      throw const DomainFailure('结束时间必须晚于开始时间');
    }
    if (end.isAfter(_now().toLocal())) {
      throw const DomainFailure('不能记录未来时间');
    }
  }

  Future<void> _validateOverlap(
    DateTime start,
    DateTime end, {
    String? exceptId,
  }) async {
    for (final other in await _all()) {
      if (other.id == exceptId) {
        continue;
      }
      final otherEnd = other.endedAt ?? _now().toLocal();
      if (start.isBefore(otherEnd.toLocal()) &&
          end.isAfter(other.startedAt.toLocal())) {
        throw DomainFailure(
          '与「${other.name} ${_range(other.startedAt, otherEnd)}」时间重叠',
        );
      }
    }
  }

  String _range(DateTime start, DateTime end) =>
      '${_clock(start)}–${_clock(end)}';
  String _clock(DateTime value) =>
      '${value.toLocal().hour.toString().padLeft(2, '0')}:${value.toLocal().minute.toString().padLeft(2, '0')}';
  Future<List<DailyExecutionSegment>> _all() async {
    final events = [
      ...await _events.getIncompleteEvents(),
      ...await _events.getCompletedEvents(),
    ];
    final eventById = {for (final e in events) e.id: e};
    final categories = await _events.getCategories();
    final eventCategoryById = {
      for (final category in categories) category.id: category,
    };
    final result = <DailyExecutionSegment>[];
    for (final s in await _events.getAllRunSegments()) {
      final e = eventById[s.eventId];
      if (e != null) {
        final root = _rootEvent(e, eventById);
        final category = root.categoryId == null
            ? null
            : eventCategoryById[root.categoryId];
        result.add(
          DailyExecutionSegment(
            id: s.id,
            source: ExecutionSource.event,
            ownerId: s.eventId,
            name: e.name,
            startedAt: s.startedAt,
            endedAt: s.endedAt,
            createdAt: s.createdAt,
            detail: category?.name ?? '未分类',
            categoryBucketKey: category == null
                ? 'unclassified'
                : 'event:${category.id}',
            categoryName: category?.name ?? '未分类',
            categoryColorKey: category?.colorKey,
          ),
        );
      }
    }
    final repo = _routines;
    if (repo == null) {
      return result;
    }
    final routines = {for (final r in await repo.getRoutines()) r.id: r};
    final routineCategories = await repo.getRoutineCategories();
    final routineCategoryById = {
      for (final category in routineCategories) category.id: category,
    };
    final executions = {
      for (final e in await repo.getRoutineExecutions()) e.id: e,
    };
    for (final s in await repo.getAllRoutineRunSegments()) {
      final e = executions[s.executionId];
      final r = e == null ? null : routines[e.routineId];
      if (r != null) {
        final category = r.routineCategoryId == null
            ? null
            : routineCategoryById[r.routineCategoryId];
        result.add(
          DailyExecutionSegment(
            id: s.id,
            source: ExecutionSource.routine,
            ownerId: s.executionId,
            name: r.name,
            startedAt: s.startedAt,
            endedAt: s.endedAt,
            createdAt: s.createdAt,
            detail: '${category?.name ?? '未分类'} · 日常',
            categoryBucketKey: category == null
                ? 'unclassified'
                : 'routine:${category.id}',
            categoryName: category?.name ?? '未分类',
            categoryColorKey: category?.colorKey,
          ),
        );
      }
    }
    return result;
  }

  JaxEvent _rootEvent(JaxEvent event, Map<String, JaxEvent> byId) {
    var current = event;
    final seen = <String>{};
    while (current.parentEventId != null && seen.add(current.id)) {
      final parent = byId[current.parentEventId];
      if (parent == null) {
        break;
      }
      current = parent;
    }
    return current;
  }
}
