import '../entities/event_day_plan.dart';

abstract interface class EventDayPlanRepository {
  Future<List<EventDayPlan>> getEventDayPlans(String dayKey);
  Future<void> addEventDayPlan(EventDayPlan plan);

  /// Appends only plans which do not already exist for the day.
  ///
  /// The given order is preserved after the existing plans, and the write is
  /// atomic for persistent implementations.
  Future<void> addEventDayPlans(List<EventDayPlan> plans);
  Future<void> removeEventDayPlan(String eventId, String dayKey);
  Future<void> reorderEventDayPlan(
    String eventId,
    String dayKey,
    int targetIndex,
  );
}
