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
  Future<JaxEvent?> getParent(String eventId) async {
    final event = await getEvent(eventId);
    return event?.parentEventId == null
        ? null
        : getEvent(event!.parentEventId!);
  }

  @override
  Future<List<JaxEvent>> getDirectChildren(String parentEventId) async =>
      _ordered(events.where((event) => event.parentEventId == parentEventId));

  @override
  Future<List<JaxEvent>> getOrderedSiblings(String eventId) async {
    final event = await getEvent(eventId);
    if (event == null) throw StateError('Event not found: $eventId');
    return _ordered(
      events.where((item) => item.parentEventId == event.parentEventId),
    );
  }

  @override
  Future<List<JaxEvent>> getOrderedTopLevelEvents() async =>
      _ordered(events.where((event) => event.parentEventId == null));

  List<JaxEvent> _ordered(Iterable<JaxEvent> source) => source.toList()
    ..sort((a, b) {
      final order = (a.sortOrder ?? 1 << 30).compareTo(b.sortOrder ?? 1 << 30);
      if (order != 0) return order;
      final created = a.createdAt.compareTo(b.createdAt);
      return created != 0 ? created : a.id.compareTo(b.id);
    });

  @override
  Future<void> updateParent(
    String eventId,
    String? parentEventId,
    DateTime updatedAt,
  ) async {
    final event = await getEvent(eventId);
    if (event == null) throw StateError('Event not found: $eventId');
    await updateEvent(
      event.copyWith(parentEventId: parentEventId, updatedAt: updatedAt),
    );
  }

  @override
  Future<void> switchRunningEvent({
    required JaxEvent pausedRunning,
    required RunSegment closedSegment,
    required JaxEvent runningTarget,
    required RunSegment newSegment,
    required List<JaxEvent> pausedAncestors,
  }) async {
    await updateEvent(pausedRunning);
    segments[segments.indexWhere((item) => item.id == closedSegment.id)] =
        closedSegment;
    for (final ancestor in pausedAncestors) {
      await updateEvent(ancestor);
    }
    await updateEvent(runningTarget);
    segments.add(newSegment);
  }

  @override
  Future<void> deleteEvent(String id) async {
    events.removeWhere((event) => event.id == id);
    segments.removeWhere((segment) => segment.eventId == id);
  }
}
