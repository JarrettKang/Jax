import '../entities/event_day_plan.dart';

abstract interface class EventDayPlanRepository {
  Future<List<EventDayPlan>> getEventDayPlans(String dayKey);
  Future<void> addEventDayPlan(EventDayPlan plan);
  Future<void> removeEventDayPlan(String eventId, String dayKey);
  Future<void> reorderEventDayPlan(
    String eventId,
    String dayKey,
    int targetIndex,
  );
}
