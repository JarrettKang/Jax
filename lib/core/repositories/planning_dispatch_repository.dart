import '../entities/jax_event.dart';

abstract interface class PlanningDispatchRepository {
  Future<List<JaxEvent>> dispatchPlanItems({
    required Map<String, String> eventIdsByPlanItemId,
    required String dayKey,
    required DateTime now,
  });
}
