import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/repositories/event_repository.dart';

class MemoryRepository implements EventRepository {
  MemoryRepository([Iterable<JaxEvent> seed = const []])
    : events = List.of(seed);
  final List<JaxEvent> events;
  @override
  Future<void> insertEvent(JaxEvent event) async => events.add(event);
  @override
  Future<List<JaxEvent>> getIncompleteEvents() async => List.of(events);
  @override
  Future<JaxEvent?> getEvent(String id) async =>
      events.where((event) => event.id == id).firstOrNull;
  @override
  Future<void> updateEvent(JaxEvent event) async =>
      events[events.indexWhere((item) => item.id == event.id)] = event;
  @override
  Future<void> deleteEvent(String id) async =>
      events.removeWhere((event) => event.id == id);
}
