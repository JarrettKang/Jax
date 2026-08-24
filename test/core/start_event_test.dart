import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/run_segment.dart';
import 'package:jax/core/use_cases/start_event.dart';

import '../support/memory_repository.dart';

void main() {
  test('starts pending event and opens a run segment', () async {
    final created = DateTime.utc(2026, 8, 24, 12);
    final started = created.add(const Duration(minutes: 2));
    final repository = MemoryRepository([
      JaxEvent(
        id: 'event',
        name: '任务',
        status: EventStatus.pending,
        createdAt: created,
        updatedAt: created,
      ),
    ]);
    final result = await StartEvent(
      repository: repository,
      newId: () => 'segment',
      now: () => started,
    )('event');
    expect(result.event.status, EventStatus.running);
    expect(result.event.firstStartedAt, started);
    expect(
      result.segment,
      RunSegment(
        id: 'segment',
        eventId: 'event',
        startedAt: started,
        createdAt: started,
      ),
    );
  });
}
