import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/run_segment.dart';
import 'package:jax/core/use_cases/resume_event.dart';

import '../support/memory_repository.dart';

void main() {
  test(
    'resumes paused event with a new segment and preserves first start',
    () async {
      final first = DateTime.utc(2026);
      final resumeAt = first.add(const Duration(hours: 1));
      final event = JaxEvent(
        id: 'one',
        name: '任务',
        status: EventStatus.paused,
        createdAt: first,
        updatedAt: first,
        firstStartedAt: first,
      );
      final repository = MemoryRepository([event])
        ..segments.add(
          RunSegment(
            id: 'old',
            eventId: 'one',
            startedAt: first,
            endedAt: first.add(const Duration(minutes: 10)),
            createdAt: first,
          ),
        );
      await ResumeEvent(
        repository: repository,
        newId: () => 'new',
        now: () => resumeAt,
      )('one');
      final resumed = (await repository.getEvent('one'))!;
      expect(resumed.status, EventStatus.running);
      expect(resumed.firstStartedAt, first);
      expect(repository.segments.last.id, 'new');
      expect(repository.segments.last.endedAt, isNull);
    },
  );
}
