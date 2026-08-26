import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/world_display_state.dart';
import 'package:jax/core/services/world_display_state_service.dart';

void main() {
  final now = DateTime.utc(2026, 8, 26);
  JaxEvent event(String id, EventStatus status, {String? parent}) => JaxEvent(
    id: id,
    name: id,
    status: status,
    parentEventId: parent,
    createdAt: now,
    updatedAt: now,
  );
  const service = WorldDisplayStateService();

  test('derives direct and deep running descendants', () {
    final states = service.derive([
      event('a', EventStatus.paused),
      event('b', EventStatus.paused, parent: 'a'),
      event('c', EventStatus.paused, parent: 'b'),
      event('d', EventStatus.running, parent: 'c'),
    ]);
    expect(states['a'], WorldDisplayState.progressing);
    expect(states['b'], WorldDisplayState.progressing);
    expect(states['c'], WorldDisplayState.progressing);
    expect(states['d'], WorldDisplayState.running);
  });

  test('waiting descendants are used unless any running descendant exists', () {
    final states = service.derive([
      event('a', EventStatus.paused),
      event('w', EventStatus.waiting, parent: 'a'),
      event('r', EventStatus.running, parent: 'a'),
    ]);
    expect(states['a'], WorldDisplayState.progressing);
    expect(states['w'], WorldDisplayState.waiting);
    expect(states['r'], WorldDisplayState.running);
  });

  test('own waiting and paused states remain distinct facts', () {
    final events = [
      event('a', EventStatus.waiting),
      event('b', EventStatus.paused),
    ];
    final states = service.derive(events);
    expect(states['a'], WorldDisplayState.waiting);
    expect(states['b'], WorldDisplayState.paused);
    expect(events[0].status, EventStatus.waiting);
  });
}
