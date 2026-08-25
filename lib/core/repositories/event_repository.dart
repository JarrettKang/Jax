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
  Future<void> pauseEvent(JaxEvent event, RunSegment segment);
  Future<JaxEvent?> getParent(String eventId);
  Future<List<JaxEvent>> getDirectChildren(String parentEventId);
  Future<List<JaxEvent>> getOrderedSiblings(String eventId);
  Future<List<JaxEvent>> getOrderedTopLevelEvents();
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
}
