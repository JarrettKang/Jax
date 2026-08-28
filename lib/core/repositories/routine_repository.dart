import '../entities/routine.dart';
import '../entities/routine_category.dart';

abstract interface class RoutineRepository {
  Future<List<Routine>> getRoutines();
  Future<List<RoutineCategory>> getRoutineCategories();
  Future<void> insertRoutineCategory(RoutineCategory category);
  Future<void> updateRoutineCategory(RoutineCategory category);
  Future<void> reorderRoutineCategory(String id, int targetIndex);
  Future<void> deleteRoutineCategory(String id);
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
  Future<List<RoutineRunSegment>> getAllRoutineRunSegments();
  Future<void> insertHistoricalRoutineExecution(
    RoutineExecution execution,
    RoutineRunSegment segment,
  );
  Future<void> updateClosedRoutineRunSegment(RoutineRunSegment segment);
  Future<void> deleteClosedRoutineRunSegment(String id);
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
