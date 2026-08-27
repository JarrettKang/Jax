import '../entities/routine.dart';

abstract interface class RoutineRepository {
  Future<List<Routine>> getRoutines();
  Future<void> insertRoutine(Routine routine);
  Future<void> updateRoutine(Routine routine);
  Future<void> reorderRoutine(String id, int targetIndex);
  Future<RoutineExecution?> getRoutineExecution(
    String routineId,
    String occurrenceDate,
  );
  Future<List<RoutineExecution>> getRoutineExecutions();
  Future<RoutineExecution?> getRunningRoutineExecution();
  Future<List<RoutineRunSegment>> getRoutineRunSegments(String executionId);
  Future<void> startRoutineExecution(
    RoutineExecution execution,
    RoutineRunSegment segment,
    DateTime now,
  );
  Future<void> pauseRoutineExecution(
    RoutineExecution execution,
    RoutineRunSegment segment,
  );
  Future<void> completeRoutineExecution(
    RoutineExecution execution,
    RoutineRunSegment segment,
  );
  Future<void> updateRoutineExecutionOnly(RoutineExecution execution);
  Future<void> pauseRunningRoutine(DateTime now);
}
