import '../entities/jax_event.dart';

/// Crossing from Planning to execution is a single storage transaction.
abstract interface class PlanningExecutionRepository {
  Future<JaxEvent> startPlanItem({
    required String planItemId,
    required String eventId,
    required String segmentId,
    required String dayKey,
    required DateTime now,
  });
}
