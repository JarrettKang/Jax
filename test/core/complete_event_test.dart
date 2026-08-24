import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/run_segment.dart';
import 'package:jax/core/use_cases/complete_event.dart';

import '../support/memory_repository.dart';

void main() {
  test(
    'completes running event and excludes paused time from duration',
    () async {
      final start = DateTime.utc(2026);
      final end = start.add(const Duration(minutes: 30));
      final event = JaxEvent(
        id: 'one',
        name: '任务',
        status: EventStatus.running,
        createdAt: start,
        updatedAt: start,
        firstStartedAt: start,
      );
      final repository = MemoryRepository([event])
        ..segments.addAll([
          RunSegment(
            id: 'old',
            eventId: 'one',
            startedAt: start,
            endedAt: start.add(const Duration(minutes: 10)),
            createdAt: start,
          ),
          RunSegment(
            id: 'open',
            eventId: 'one',
            startedAt: start.add(const Duration(minutes: 20)),
            createdAt: start,
          ),
        ]);
      final record = await CompleteEvent(
        repository: repository,
        now: () => end,
      )('one');
      expect(record.event.status, EventStatus.completed);
      expect(record.event.completedAt, end);
      expect(record.duration, const Duration(minutes: 20));
      expect(await repository.getIncompleteEvents(), isEmpty);
    },
  );
}
