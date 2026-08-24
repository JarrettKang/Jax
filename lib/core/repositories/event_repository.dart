import '../entities/jax_event.dart';
import '../entities/run_segment.dart';

abstract interface class EventRepository {
  Future<void> insertEvent(JaxEvent event);
  Future<List<JaxEvent>> getIncompleteEvents();
  Future<JaxEvent?> getEvent(String id);
  Future<void> updateEvent(JaxEvent event);
  Future<void> deleteEvent(String id);
  Future<void> startEvent(JaxEvent event, RunSegment segment);
  Future<List<RunSegment>> getRunSegments(String eventId);
}
