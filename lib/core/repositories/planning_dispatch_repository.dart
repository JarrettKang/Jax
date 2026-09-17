import '../entities/jax_event.dart';

abstract interface class PlanningDispatchRepository {
  /// Rechecks execution facts and withdraws the linked Event atomically.
  /// Legacy unstarted Events are restored to next.
  Future<void> withdrawPlanItem({
    required String planItemId,
    required DateTime now,
  });

  /// Legacy compatibility API. No product UI calls this; use startPlanItem.
  Future<List<JaxEvent>> dispatchPlanItems({
    required Map<String, String> eventIdsByPlanItemId,
    required String dayKey,
    required DateTime now,
  });
}
