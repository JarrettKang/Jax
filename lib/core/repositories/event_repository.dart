import '../entities/jax_event.dart';
import '../entities/run_segment.dart';
import '../entities/category.dart';

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
  Future<void> deleteClosedRunSegment(String id);
  Future<void> pauseEvent(JaxEvent event, RunSegment segment);
  Future<void> restoreCompletedEvents(List<JaxEvent> events);
  Future<JaxEvent?> getParent(String eventId);
  Future<List<JaxEvent>> getDirectChildren(String parentEventId);
  Future<List<JaxEvent>> getOrderedSiblings(String eventId);
  Future<List<JaxEvent>> getOrderedTopLevelEvents();
  Future<void> reorderSibling(String eventId, int targetIndex);
  Future<void> updateParent(
    String eventId,
    String? parentEventId,
    DateTime updatedAt,
  );
  Future<void> switchRunningEvent({
    required JaxEvent pausedRunning,
    required RunSegment closedSegment,
    required JaxEvent runningTarget,
    required RunSegment newSegment,
    required List<JaxEvent> pausedAncestors,
  });
  Future<List<Category>> getCategories();
  Future<void> insertCategory(Category category);
  Future<void> updateCategory(Category category);
  Future<void> deleteCategory(String id);
  Future<void> reorderCategory(String id, int targetIndex);
  Future<void> setRootCategory(String eventId, String? categoryId);
}
