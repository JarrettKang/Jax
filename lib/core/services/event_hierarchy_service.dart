import '../entities/event_status.dart';
import '../entities/jax_event.dart';
import '../errors/domain_failure.dart';
import '../repositories/event_repository.dart';

class EventHierarchyService {
  const EventHierarchyService(this.repository);
  final EventRepository repository;

  Future<List<JaxEvent>> parentCandidates(String eventId) async {
    final current = await _required(eventId);
    final descendants = await _descendantIds(eventId);
    return (await _allEvents())
        .where((event) => event.id != eventId)
        .where((event) => !descendants.contains(event.id))
        .where(
          (event) =>
              current.status == EventStatus.completed ||
              event.status != EventStatus.completed,
        )
        .toList(growable: false);
  }

  Future<List<JaxEvent>> childCandidates(String eventId) async {
    final current = await _required(eventId);
    final ancestors = await _ancestorIds(eventId);
    return (await _allEvents())
        .where((event) => event.id != eventId)
        .where((event) => !ancestors.contains(event.id))
        .where(
          (event) =>
              current.status != EventStatus.completed ||
              event.status == EventStatus.completed,
        )
        .toList(growable: false);
  }

  Future<Set<String>> _descendantIds(String eventId) async {
    final result = <String>{};
    final pending = <String>[eventId];
    while (pending.isNotEmpty) {
      for (final child in await repository.getDirectChildren(
        pending.removeLast(),
      )) {
        if (result.add(child.id)) pending.add(child.id);
      }
    }
    return result;
  }

  Future<Set<String>> _ancestorIds(String eventId) async {
    final result = <String>{};
    var current = await repository.getParent(eventId);
    while (current != null && result.add(current.id)) {
      current = await repository.getParent(current.id);
    }
    return result;
  }

  Future<List<JaxEvent>> _allEvents() async => [
    ...await repository.getIncompleteEvents(),
    ...await repository.getCompletedEvents(),
  ];

  Future<JaxEvent> _required(String id) async =>
      await repository.getEvent(id) ?? (throw const DomainFailure('事件不存在'));
}
