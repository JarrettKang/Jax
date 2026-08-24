import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/run_segment.dart';
import 'package:jax/core/repositories/event_repository.dart';

class MemoryRepository implements EventRepository {
  MemoryRepository([Iterable<JaxEvent> seed = const []])
    : events = List.of(seed);
  final List<JaxEvent> events;
  final List<RunSegment> segments = [];
  @override
  Future<void> insertEvent(JaxEvent event) async => events.add(event);
  @override
  Future<List<JaxEvent>> getIncompleteEvents() async =>
      events.where((event) => event.status.name != 'completed').toList();
  @override
  Future<List<JaxEvent>> getCompletedEvents() async =>
      events.where((event) => event.status.name == 'completed').toList();
  @override
  Future<JaxEvent?> getEvent(String id) async =>
      events.where((event) => event.id == id).firstOrNull;
  @override
  Future<void> updateEvent(JaxEvent event) async =>
      events[events.indexWhere((item) => item.id == event.id)] = event;
  @override
  Future<void> startEvent(JaxEvent event, RunSegment segment) async {
    await updateEvent(event);
    segments.add(segment);
  }

  @override
  Future<List<RunSegment>> getRunSegments(String eventId) async =>
      segments.where((segment) => segment.eventId == eventId).toList();
  @override
  Future<void> pauseEvent(JaxEvent event, RunSegment segment) async {
    await updateEvent(event);
    segments[segments.indexWhere((item) => item.id == segment.id)] = segment;
  }

  @override
  Future<void> deleteEvent(String id) async =>
      events.removeWhere((event) => event.id == id);
}
