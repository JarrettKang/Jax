import '../entities/jax_event.dart';

abstract interface class EventRepository {
  Future<void> insertEvent(JaxEvent event);
  Future<List<JaxEvent>> getIncompleteEvents();
  Future<JaxEvent?> getEvent(String id);
  Future<void> updateEvent(JaxEvent event);
}
