import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/run_segment.dart';
import 'package:jax/core/services/hierarchy_duration_service.dart';

import '../support/memory_repository.dart';

void main() {
  final base = DateTime.utc(2026, 8, 25, 8);
  JaxEvent event(String id, {String? parent}) => JaxEvent(
    id: id,
    name: id,
    status: EventStatus.completed,
    parentEventId: parent,
    createdAt: base,
    updatedAt: base,
  );
  RunSegment segment(String id, String eventId, int start, int end) =>
      RunSegment(
        id: id,
        eventId: eventId,
        startedAt: base.add(Duration(minutes: start)),
        endedAt: base.add(Duration(minutes: end)),
        createdAt: base,
      );

  test('direct duration sums only the Event own segments', () async {
    final repository =
        MemoryRepository([event('root'), event('child', parent: 'root')])
          ..segments.addAll([
            segment('root-1', 'root', 0, 5),
            segment('root-2', 'root', 10, 17),
            segment('child-1', 'child', 0, 30),
          ]);
    final service = HierarchyDurationService(repository, now: () => base);

    expect(await service.directDuration('root'), const Duration(minutes: 12));
  });

  test(
    'total duration sums direct time at every descendant depth once',
    () async {
      final repository =
          MemoryRepository([
              event('root'),
              event('child', parent: 'root'),
              event('grandchild', parent: 'child'),
            ])
            ..segments.addAll([
              segment('root', 'root', 0, 2),
              segment('child-a', 'child', 0, 3),
              segment('child-b', 'child', 5, 9),
              segment('grandchild', 'grandchild', 0, 5),
            ]);
      final service = HierarchyDurationService(repository, now: () => base);

      expect(await service.totalDuration('root'), const Duration(minutes: 14));
      expect(await service.totalDuration('child'), const Duration(minutes: 12));
    },
  );

  test(
    'moving hierarchy recalculates totals without changing segments',
    () async {
      final repository = MemoryRepository([
        event('first'),
        event('second'),
        event('child', parent: 'first'),
      ])..segments.add(segment('child', 'child', 0, 8));
      final service = HierarchyDurationService(repository, now: () => base);

      expect(await service.totalDuration('first'), const Duration(minutes: 8));
      expect(await service.totalDuration('second'), Duration.zero);
      await repository.updateParent('child', 'second', base);
      expect(await service.totalDuration('first'), Duration.zero);
      expect(await service.totalDuration('second'), const Duration(minutes: 8));
      expect(repository.segments, hasLength(1));
    },
  );

  test('open segment uses the injected clock', () async {
    final repository = MemoryRepository([event('running')])
      ..segments.add(
        RunSegment(
          id: 'open',
          eventId: 'running',
          startedAt: base,
          createdAt: base,
        ),
      );
    final service = HierarchyDurationService(
      repository,
      now: () => base.add(const Duration(minutes: 6)),
    );

    expect(await service.totalDuration('running'), const Duration(minutes: 6));
  });
}
