import '../entities/event_status.dart';
import '../entities/jax_event.dart';
import '../entities/world_display_state.dart';

/// Derives structure-only display states without changing Event facts.
class WorldDisplayStateService {
  const WorldDisplayStateService();

  Map<String, WorldDisplayState> derive(Iterable<JaxEvent> events) {
    final all = events.toList(growable: false);
    final byId = {for (final event in all) event.id: event};
    final children = <String, List<JaxEvent>>{};
    for (final event in all) {
      final parent = event.parentEventId;
      if (parent != null && byId.containsKey(parent)) {
        children.putIfAbsent(parent, () => []).add(event);
      }
    }
    final memo = <String, WorldDisplayState>{};
    WorldDisplayState visit(JaxEvent event) {
      final cached = memo[event.id];
      if (cached != null) return cached;
      final descendantStates = (children[event.id] ?? const <JaxEvent>[])
          .map(visit)
          .toList();
      final state = _derive(event.status, descendantStates);
      memo[event.id] = state;
      return state;
    }

    for (final event in all) {
      visit(event);
    }
    return memo;
  }

  WorldDisplayState _derive(
    EventStatus status,
    List<WorldDisplayState> descendants,
  ) {
    if (status == EventStatus.running) return WorldDisplayState.running;
    if (descendants.contains(WorldDisplayState.running) ||
        descendants.contains(WorldDisplayState.progressing)) {
      return WorldDisplayState.progressing;
    }
    if (status == EventStatus.waiting ||
        descendants.contains(WorldDisplayState.waiting)) {
      return WorldDisplayState.waiting;
    }
    return switch (status) {
      EventStatus.pending => WorldDisplayState.pending,
      EventStatus.paused => WorldDisplayState.paused,
      EventStatus.running => WorldDisplayState.running,
      EventStatus.waiting => WorldDisplayState.waiting,
      EventStatus.completed => WorldDisplayState.completed,
    };
  }
}
