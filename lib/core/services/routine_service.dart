import '../entities/routine.dart';
import '../entities/jax_day.dart';
import '../errors/domain_failure.dart';
import '../repositories/routine_repository.dart';
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
    String? categoryId,
    RoutineRecurrence recurrence,
    int mask,
  ) async {
    final clean = name.trim();
    if (clean.isEmpty) throw const DomainFailure('日常名称不能为空');
    if (recurrence == RoutineRecurrence.selectedWeekdays && mask == 0) {
      throw const DomainFailure('请至少选择一天');
    }
    final t = now().toUtc();
    final all = await repository.getRoutines();
    await repository.insertRoutine(
      Routine(
        id: newId(),
        name: clean,
        categoryId: categoryId,
        recurrence: recurrence,
        weekdayMask: mask,
        isActive: true,
        sortOrder: all.length,
        createdAt: t,
        updatedAt: t,
      ),
    );
  }

  Future<void> update(
    Routine routine,
    String name,
    String? categoryId,
    RoutineRecurrence recurrence,
    int mask,
  ) async {
    final clean = name.trim();
    if (clean.isEmpty) throw const DomainFailure('日常名称不能为空');
    if (recurrence == RoutineRecurrence.selectedWeekdays && mask == 0) {
      throw const DomainFailure('请至少选择一天');
    }
    await repository.updateRoutine(
      routine.copyWith(
        name: clean,
        categoryId: categoryId,
        clearCategory: categoryId == null,
        recurrence: recurrence,
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
    if (execution?.status == RoutineExecutionStatus.completed) {
      throw StateError('今天已经完成');
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
    await repository.startRoutineExecution(
      e.copyWith(status: RoutineExecutionStatus.running, updatedAt: t),
      RoutineRunSegment(
        id: newId(),
        executionId: e.id,
        startedAt: t,
        createdAt: t,
      ),
      t,
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
  }

  Future<void> complete(RoutineExecution e) async {
    final t = now().toUtc();
    final open = (await repository.getRoutineRunSegments(e.id))
        .where((s) => s.endedAt == null)
        .firstOrNull;
    final done = e.copyWith(
      status: RoutineExecutionStatus.completed,
      updatedAt: t,
      completedAt: t,
    );
    if (open == null) {
      await repository.updateRoutineExecutionOnly(done);
    } else {
      await repository.completeRoutineExecution(
        done,
        open.copyWith(endedAt: t),
      );
    }
  }
}
