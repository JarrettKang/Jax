import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/run_segment.dart';
import 'package:jax/core/use_cases/pause_event.dart';

import '../support/memory_repository.dart';

void main() {
  test('pauses running event and closes its open segment', () async {
    final start = DateTime.utc(2026);
    final end = start.add(const Duration(minutes: 5));
    final event = JaxEvent(
      id: 'one',
      name: '任务',
      status: EventStatus.running,
      createdAt: start,
      updatedAt: start,
      firstStartedAt: start,
    );
    final repository = MemoryRepository([event])
      ..segments.add(
        RunSegment(
          id: 'segment',
          eventId: 'one',
          startedAt: start,
          createdAt: start,
        ),
      );
    await PauseEvent(repository: repository, now: () => end)('one');
    expect((await repository.getEvent('one'))!.status, EventStatus.paused);
    expect(repository.segments.single.endedAt, end);
    expect(
      repository.segments.single.durationAt(end.add(const Duration(hours: 1))),
      const Duration(minutes: 5),
    );
  });
}
