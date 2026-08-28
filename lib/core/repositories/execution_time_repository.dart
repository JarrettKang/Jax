import '../entities/execution_time_segment.dart';

abstract interface class ExecutionTimeRepository {
  Future<List<ExecutionTimeOwner>> getEditableExecutionTimeOwners();
  Future<bool> canCompleteExecutionOwner(
    ExecutionOwnerType ownerType,
    String ownerId,
  );
  Future<List<ExecutionTimeSegment>> getAllExecutionTimeSegments();
  Future<void> insertExecutionTimeSegment(ExecutionTimeSegment segment);
  Future<void> updateExecutionTimeSegment(ExecutionTimeSegment segment);
  Future<void> deleteExecutionTimeSegment(
    ExecutionOwnerType ownerType,
    String segmentId,
  );
  Future<void> finishRunningAt({
    required ExecutionOwnerType ownerType,
    required String ownerId,
    required String segmentId,
    required DateTime endedAt,
    required bool complete,
  });
}
