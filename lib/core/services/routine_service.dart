import '../entities/routine.dart';
import '../entities/jax_day.dart';
import '../errors/domain_failure.dart';
import '../repositories/routine_repository.dart';
import 'segment_lifecycle_log.dart';
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
  }) async {
    final clean = name.trim();
    if (clean.isEmpty) throw const DomainFailure('日常名称不能为空');
    if (type == RoutineType.scheduled &&
        recurrence == RoutineRecurrence.selectedWeekdays &&
        mask == 0) {
      throw const DomainFailure('请至少选择一天');
    }
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
  }) async {
    final clean = name.trim();
    if (clean.isEmpty) throw const DomainFailure('日常名称不能为空');
    final nextType = type ?? routine.type;
    if (nextType == RoutineType.scheduled &&
        recurrence == RoutineRecurrence.selectedWeekdays &&
        mask == 0) {
      throw const DomainFailure('请至少选择一天');
    }
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
        weekdayMask: mask,
        updatedAt: now().toUtc(),
      ),
    );
  }

  Future<void> setActive(Routine r, bool active) => repository.updateRoutine(
    r.copyWith(isActive: active, updatedAt: now().toUtc()),
  );
  Future<void> start(Routine r, {RoutineExecution? execution}) async {
    final t = now().toUtc();
    final day = occurrence(t.toLocal());
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

  Future<void> pause(RoutineExecution e) async {
    final t = now().toUtc();
    final open = (await repository.getRoutineRunSegments(e.id))
        .where((s) => s.endedAt == null)
        .first;
    await repository.pauseRoutineExecution(
      e.copyWith(status: RoutineExecutionStatus.paused, updatedAt: t),
      open.copyWith(endedAt: t),
    );
    SegmentLifecycleLog.close(
      reason: 'routine_pause',
      ownerType: 'routine',
      ownerId: e.routineId,
      executionId: e.id,
      segmentId: open.id,
      startedAt: open.startedAt,
      endedAt: t,
    );
  }

  Future<void> complete(RoutineExecution e, {DateTime? endTime}) async {
    final t = now().toUtc();
    final open = (await repository.getRoutineRunSegments(e.id))
        .where((s) => s.endedAt == null)
        .firstOrNull;
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
      await repository.updateRoutineExecutionOnly(done);
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
