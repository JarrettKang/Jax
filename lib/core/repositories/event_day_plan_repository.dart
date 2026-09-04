import '../entities/event_day_plan.dart';

abstract interface class EventDayPlanRepository {
  Future<List<EventDayPlan>> getEventDayPlans(String dayKey);
  Future<void> addEventDayPlan(EventDayPlan plan);

  /// Appends only plans which do not already exist for the day.
  ///
  /// The given order is preserved after the existing plans, and the write is
  /// atomic for persistent implementations.
  Future<void> addEventDayPlans(List<EventDayPlan> plans);

  /// Initializes [currentDayKey] once by appending unfinished Events from the
  /// final ordering of [previousDayKey].
  ///
  /// Implementations must atomically persist the initialization decision even
  /// when there is nothing to carry. This prevents a later status restoration
  /// or a same-day Today removal from being interpreted as a new carry-over.
  Future<void> initializeDayFromPrevious({
    required String previousDayKey,
    required String currentDayKey,
    required DateTime initializedAt,
  });
  Future<void> removeEventDayPlan(String eventId, String dayKey);
  Future<void> reorderEventDayPlan(
    String eventId,
    String dayKey,
    int targetIndex,
  );
}
