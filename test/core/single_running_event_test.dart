import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/run_segment.dart';
import 'package:jax/core/use_cases/start_event.dart';

import '../support/memory_repository.dart';

void main() {
  test(
    'atomically switches between unrelated flat Events',
    () async {
      final time = DateTime.utc(2026);
      JaxEvent event(String id, EventStatus status) => JaxEvent(
        id: id,
        name: id,
        status: status,
        createdAt: time,
        updatedAt: time,
        firstStartedAt: status == EventStatus.running ? time : null,
      );
      final repository = MemoryRepository([
        event('running', EventStatus.running),
        event('pending', EventStatus.pending),
      ])..segments.add(
          RunSegment(
            id: 'open',
            eventId: 'running',
            startedAt: time,
            createdAt: time,
          ),
        );
      final start = StartEvent(
        repository: repository,
        newId: () => 'segment',
        now: () => time,
      );
      await start('pending');
      expect(
        (await repository.getEvent('running'))!.status,
        EventStatus.paused,
      );
      expect(
        (await repository.getEvent('pending'))!.status,
        EventStatus.running,
      );
      expect(repository.segments, hasLength(2));
      expect(repository.segments.first.endedAt, time);
      expect(repository.segments.last.eventId, 'pending');
    },
  );
}
