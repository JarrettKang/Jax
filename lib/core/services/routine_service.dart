import '../entities/execution_capabilities.dart';
import '../entities/routine.dart';
import '../entities/jax_day.dart';
import '../errors/domain_failure.dart';
import '../repositories/routine_repository.dart';
import 'segment_lifecycle_log.dart';
import 'temporal_routine.dart';
import '../use_cases/create_event.dart';

class RoutineService {
  RoutineService({
    required this.repository,
    required this.newId,
    required this.now,
  });
  final RoutineRepository repository;
  final IdGenerator newId;
  final Clock now;
  static String occurrence(DateTime date) => JaxDay.containing(date).key;
  Future<void> create(
    String name,
    String? routineCategoryId,
    RoutineRecurrence recurrence,
    int mask, {
    RoutineType type = RoutineType.scheduled,
    bool showInHomeQuickActions = false,
    RoutineTimeRecommendation? timeRecommendation,
  }) async {
    final clean = name.trim();
    if (clean.isEmpty) throw const DomainFailure('日常名称不能为空');
    if (type == RoutineType.scheduled &&
        recurrence == RoutineRecurrence.selectedWeekdays &&
        mask == 0) {
      throw const DomainFailure('请至少选择一天');
    }
    _validateTimeRecommendation(type, timeRecommendation);
    final t = now().toUtc();
    final all = (await repository.getRoutines())
        .where((r) => r.routineCategoryId == routineCategoryId)
        .toList();
    final nextOrder =
        all.fold<int>(
          -1,
          (value, r) => r.sortOrder > value ? r.sortOrder : value,
        ) +
        1;
    await repository.insertRoutine(
      Routine(
        id: newId(),
        name: clean,
        routineCategoryId: routineCategoryId,
        recurrence: recurrence,
        type: type,
        showInHomeQuickActions:
            type == RoutineType.onDemand && showInHomeQuickActions,
        timeRecommendation: type == RoutineType.scheduled
            ? timeRecommendation
            : null,
        weekdayMask: mask,
        isActive: true,
        sortOrder: nextOrder,
        createdAt: t,
        updatedAt: t,
      ),
    );
  }

  Future<void> update(
    Routine routine,
    String name,
    String? routineCategoryId,
    RoutineRecurrence recurrence,
    int mask, {
    RoutineType? type,
    bool? showInHomeQuickActions,
    RoutineTimeRecommendation? timeRecommendation,
    bool updateTimeRecommendation = false,
  }) async {
    final clean = name.trim();
    if (clean.isEmpty) throw const DomainFailure('日常名称不能为空');
    final nextType = type ?? routine.type;
    if (nextType == RoutineType.scheduled &&
        recurrence == RoutineRecurrence.selectedWeekdays &&
        mask == 0) {
      throw const DomainFailure('请至少选择一天');
    }
    final nextTimeRecommendation = nextType == RoutineType.onDemand
        ? null
        : updateTimeRecommendation
        ? timeRecommendation
        : routine.timeRecommendation;
    _validateTimeRecommendation(nextType, nextTimeRecommendation);
    if (nextType != routine.type &&
        await repository.getUnfinishedRoutineExecution(routine.id) != null) {
      throw const DomainFailure('请先完成当前日常执行，再切换类型');
    }
    final changedCategory = routine.routineCategoryId != routineCategoryId;
    final destinationItems = changedCategory
        ? (await repository.getRoutines()).where(
            (r) => r.routineCategoryId == routineCategoryId,
          )
        : const <Routine>[];
    final destination = changedCategory
        ? destinationItems.fold<int>(
                -1,
                (value, r) => r.sortOrder > value ? r.sortOrder : value,
              ) +
              1
        : routine.sortOrder;
    await repository.updateRoutine(
      routine.copyWith(
        name: clean,
        routineCategoryId: routineCategoryId,
        clearCategory: routineCategoryId == null,
        sortOrder: destination,
        recurrence: recurrence,
        type: nextType,
        showInHomeQuickActions:
            nextType == RoutineType.onDemand &&
            (showInHomeQuickActions ??
                (routine.type == nextType && routine.showInHomeQuickActions)),
        timeRecommendation: nextTimeRecommendation,
        weekdayMask: mask,
        updatedAt: now().toUtc(),
      ),
    );
  }

  void _validateTimeRecommendation(
    RoutineType type,
    RoutineTimeRecommendation? configuration,
  ) {
    if (configuration == null) return;
    if (type != RoutineType.scheduled) {
      throw const DomainFailure('只有计划型日常支持按时间推荐');
    }
    TemporalRoutine.validate(configuration);
  }

  Future<void> setActive(Routine r, bool active) => repository.updateRoutine(
    r.copyWith(isActive: active, updatedAt: now().toUtc()),
  );
  Future<void> start(
    Routine r, {
    RoutineExecution? execution,
    String? occurrenceDayKey,
  }) async {
    final t = now().toUtc();
    if (execution != null) {
      final current = (await repository.getRoutineExecutions())
          .where((e) => e.id == execution!.id)
          .firstOrNull;
      if (current == null ||
          current.status == RoutineExecutionStatus.completed) {
        throw const DomainFailure('该执行已完成或不存在，请刷新');
      }
      execution = current;
    }
    final day = r.isScheduled
        ? (occurrenceDayKey ?? TemporalRoutine.occurrenceKey(r, t))
        : occurrence(t.toLocal());
    if (execution != null && execution.routineId != r.id) {
      throw const DomainFailure('执行记录与日常不一致');
    }
    if (occurrenceDayKey != null &&
        execution?.status != RoutineExecutionStatus.waiting) {
      final valid = TemporalRoutine.windows(r, JaxDay.containing(t)).any(
        (window) =>
            window.occurrenceKey == occurrenceDayKey &&
            window.stateAt(t) != TemporalRecommendationState.expired,
      );
      if (!valid) throw const DomainFailure('该时间事项已变化或失效，请刷新');
    }
    if (occurrenceDayKey != null &&
        execution != null &&
        execution.occurrenceDate != occurrenceDayKey) {
      throw const DomainFailure('执行记录与日常日期不一致');
    }
    if (r.isScheduled) {
      execution ??= await repository.getRoutineExecution(r.id, day);
    }
    if (r.isScheduled &&
        execution?.status == RoutineExecutionStatus.completed) {
      throw StateError('今天已经完成');
    }
    if (!r.isScheduled) {
      execution ??= await repository.getUnfinishedRoutineExecution(r.id);
    }
    final e =
        execution ??
        RoutineExecution(
          id: newId(),
          routineId: r.id,
          occurrenceDate: day,
          status: RoutineExecutionStatus.running,
          createdAt: t,
          updatedAt: t,
        );
    final segment = RoutineRunSegment(
      id: newId(),
      executionId: e.id,
      startedAt: t,
      createdAt: t,
    );
    await repository.startRoutineExecution(
      e.copyWith(status: RoutineExecutionStatus.running, updatedAt: t),
      segment,
      t,
    );
    SegmentLifecycleLog.open(
      reason: execution == null ? 'routine_start' : 'routine_resume',
      ownerType: 'routine',
      ownerId: r.id,
      executionId: e.id,
      segmentId: segment.id,
      startedAt: t,
    );
  }

  Future<void> wait(RoutineExecution e) =>
      _stop(e, RoutineExecutionStatus.waiting);

  Future<void> pause(RoutineExecution e) =>
      _stop(e, RoutineExecutionStatus.paused);

  Future<void> _stop(RoutineExecution e, RoutineExecutionStatus status) async {
    e = await _current(e);
    if (e.status != RoutineExecutionStatus.running) {
      throw const DomainFailure('只有正在执行的日常可以暂停或等待');
    }
    final t = now().toUtc();
    final open = (await repository.getRoutineRunSegments(e.id))
        .where((s) => s.endedAt == null)
        .first;
    await repository.pauseRoutineExecution(
      e.copyWith(status: status, updatedAt: t),
      open.copyWith(endedAt: t),
    );
    SegmentLifecycleLog.close(
      reason: status == RoutineExecutionStatus.waiting
          ? 'routine_wait'
          : 'routine_pause',
      ownerType: 'routine',
      ownerId: e.routineId,
      executionId: e.id,
      segmentId: open.id,
      startedAt: open.startedAt,
      endedAt: t,
    );
  }

  Future<RoutineExecution> _current(RoutineExecution e) async {
    final current = (await repository.getRoutineExecutions())
        .where((x) => x.id == e.id)
        .firstOrNull;
    if (current == null || current.status == RoutineExecutionStatus.completed) {
      throw const DomainFailure('该执行已完成或不存在，请刷新');
    }
    return current;
  }

  Future<void> complete(RoutineExecution e, {DateTime? endTime}) async {
    final current = await _current(e);
    if (e.status == RoutineExecutionStatus.paused &&
        (current.status != e.status || current.updatedAt != e.updatedAt)) {
      throw const DomainFailure('当前执行状态已发生变化，请重新操作');
    }
    e = current;
    if (!e.status.canComplete) throw const DomainFailure('该执行不能完成');
    final t = now().toUtc();
    final open = (await repository.getRoutineRunSegments(e.id))
        .where((s) => s.endedAt == null)
        .firstOrNull;
    if (e.status == RoutineExecutionStatus.paused && open != null) {
      throw const DomainFailure('暂停状态存在未关闭的执行段，请检查执行数据');
    }
    final correctedEnd = endTime?.toUtc() ?? t;
    if (endTime != null &&
        open != null &&
        !correctedEnd.isAfter(open.startedAt)) {
      throw const DomainFailure('结束时间必须晚于开始时间');
    }
    if (endTime != null && correctedEnd.isAfter(t)) {
      throw const DomainFailure('结束时间不能晚于当前时间');
    }
    final done = e.copyWith(
      status: RoutineExecutionStatus.completed,
      updatedAt: t,
      completedAt: correctedEnd,
    );
    if (open == null) {
      await repository.updateRoutineExecutionOnly(
        done,
        expectedPaused: e.status == RoutineExecutionStatus.paused ? e : null,
      );
    } else {
      await repository.completeRoutineExecution(
        done,
        open.copyWith(endedAt: correctedEnd),
      );
      SegmentLifecycleLog.close(
        reason: 'routine_complete',
        ownerType: 'routine',
        ownerId: e.routineId,
        executionId: e.id,
        segmentId: open.id,
        startedAt: open.startedAt,
        endedAt: correctedEnd,
      );
    }
  }
}
