import '../entities/category.dart';
import '../entities/jax_event.dart';
import '../entities/run_segment.dart';

abstract interface class EventRepository {
  Future<void> insertEvent(JaxEvent event);
  Future<List<JaxEvent>> getIncompleteEvents();
  Future<List<JaxEvent>> getCompletedEvents();
  Future<JaxEvent?> getEvent(String id);
  Future<void> updateEvent(JaxEvent event);
  Future<void> deleteEvent(String id);
  Future<void> startEvent(JaxEvent event, RunSegment segment);
  Future<List<RunSegment>> getRunSegments(String eventId);
  Future<List<RunSegment>> getAllRunSegments();
  Future<void> insertHistoricalRunSegment(RunSegment segment);
  Future<void> updateClosedRunSegment(RunSegment segment);
  Future<void> adjustRunningEventStart({
    required String eventId,
    required String segmentId,
    required DateTime expectedStartedAt,
    required DateTime newStartedAt,
    required DateTime updatedAt,
  });
  Future<void> deleteClosedRunSegment(String id);
  Future<void> pauseEvent(JaxEvent event, RunSegment segment);
  Future<void> restoreCompletedEvents(List<JaxEvent> events);
  Future<void> switchRunningEvent({
    required JaxEvent pausedRunning,
    required RunSegment closedSegment,
    required JaxEvent runningTarget,
    required RunSegment newSegment,
  });
  Future<String?> getEffectiveCategoryId(String eventId);
  Future<List<Category>> getCategories();
  Future<void> insertCategory(Category category);
  Future<void> updateCategory(Category category);
  Future<void> deleteCategory(String id);
  Future<void> reorderCategory(String id, int targetIndex);
  Future<void> setStandaloneCategory(String eventId, String? categoryId);
}
