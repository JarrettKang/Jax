import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/run_segment.dart';
import 'package:jax/core/use_cases/edit_event.dart';
import 'package:jax/core/use_cases/restore_event.dart';

import '../support/memory_repository.dart';

void main() {
  final now = DateTime.utc(2026, 9, 1, 8);

  test('flat Event edit preserves source and execution facts', () async {
    final event = JaxEvent(
      id: 'event',
      name: 'before',
      status: EventStatus.paused,
      sourcePlanItemId: 'item',
      firstStartedAt: now,
      createdAt: now,
      updatedAt: now,
    );
    final repository = MemoryRepository([event]);
    await EditEvent(repository: repository, now: () => now)('event', 'after');
    final updated = (await repository.getEvent('event'))!;
    expect(updated.name, 'after');
    expect(updated.sourcePlanItemId, 'item');
    expect(updated.firstStartedAt, now);
  });

  test('restore affects only the selected flat Event', () async {
    final completed = JaxEvent(
      id: 'done',
      name: 'done',
      status: EventStatus.completed,
      firstStartedAt: now,
      completedAt: now.add(const Duration(minutes: 5)),
      createdAt: now,
      updatedAt: now,
    );
    final other = JaxEvent(
      id: 'other',
      name: 'other',
      status: EventStatus.completed,
      completedAt: now,
      createdAt: now,
      updatedAt: now,
    );
    final repository = MemoryRepository([completed, other])
      ..segments.add(
        RunSegment(
          id: 'segment',
          eventId: 'done',
          startedAt: now,
          endedAt: now.add(const Duration(minutes: 5)),
          createdAt: now,
        ),
      );

    await RestoreEvent(repository: repository, now: () => now)('done');
    expect((await repository.getEvent('done'))!.status, EventStatus.paused);
    expect((await repository.getEvent('other'))!.status, EventStatus.completed);
    expect(await repository.getRunSegments('done'), hasLength(1));
  });
}
