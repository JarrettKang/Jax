import '../entities/jax_event.dart';

abstract interface class PlanningDispatchRepository {
  /// Rechecks execution facts and withdraws the linked Event atomically.
  /// This version restores draft because pre-dispatch priority is not stored.
  Future<void> withdrawPlanItem({
    required String planItemId,
    required DateTime now,
  });

  Future<List<JaxEvent>> dispatchPlanItems({
    required Map<String, String> eventIdsByPlanItemId,
    required String dayKey,
    required DateTime now,
  });
}
