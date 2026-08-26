import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/run_segment.dart';
import 'package:jax/core/errors/domain_failure.dart';
import 'package:jax/core/services/hierarchy_duration_service.dart';
import 'package:jax/core/use_cases/complete_event.dart';
import 'package:jax/core/use_cases/restore_event.dart';

import '../support/memory_repository.dart';

void main() {
  final time = DateTime.utc(2026, 8, 26, 8);
  JaxEvent event(
    String id,
    EventStatus status, {
    String? parent,
    int order = 0,
  }) => JaxEvent(
    id: id,
    name: id,
    status: status,
    parentEventId: parent,
    sortOrder: order,
    firstStartedAt: status == EventStatus.pending ? null : time,
    completedAt: status == EventStatus.completed
        ? time.add(const Duration(minutes: 5))
        : null,
    createdAt: time,
    updatedAt: time,
  );

  test(
    'restores completed event to paused and preserves execution facts',
    () async {
      final completed = event('done', EventStatus.completed, order: 2);
      final repository = MemoryRepository([completed])
        ..segments.add(
          RunSegment(
            id: 'segment',
            eventId: completed.id,
            startedAt: time,
            endedAt: time.add(const Duration(minutes: 5)),
            createdAt: time,
          ),
        );

      await RestoreEvent(repository: repository, now: () => time)('done');

      final restored = (await repository.getEvent('done'))!;
      expect(restored.status, EventStatus.paused);
      expect(restored.completedAt, isNull);
      expect(restored.firstStartedAt, time);
      expect(restored.parentEventId, isNull);
      expect(restored.sortOrder, 2);
      expect(await repository.getRunSegments('done'), hasLength(1));
      expect(
        await HierarchyDurationService(
          repository,
          now: () => time,
        ).directDuration('done'),
        const Duration(minutes: 5),
      );
    },
  );

  test(
    'restores all completed ancestors but stops at paused ancestor',
    () async {
      final repository = MemoryRepository([
        event('paused-root', EventStatus.paused),
        event('completed-root', EventStatus.completed, parent: 'paused-root'),
        event('parent', EventStatus.completed, parent: 'completed-root'),
        event('leaf', EventStatus.completed, parent: 'parent'),
      ]);

      await RestoreEvent(repository: repository, now: () => time)('leaf');

      expect((await repository.getEvent('leaf'))!.status, EventStatus.paused);
      expect((await repository.getEvent('parent'))!.status, EventStatus.paused);
      expect(
        (await repository.getEvent('completed-root'))!.status,
        EventStatus.paused,
      );
      expect(
        (await repository.getEvent('paused-root'))!.status,
        EventStatus.paused,
      );
    },
  );

  test(
    'does not restore completed descendants or affect another running event',
    () async {
      final repository =
          MemoryRepository([
              event('running', EventStatus.running),
              event('parent', EventStatus.completed),
              event('child', EventStatus.completed, parent: 'parent'),
            ])
            ..segments.add(
              RunSegment(
                id: 'open',
                eventId: 'running',
                startedAt: time,
                createdAt: time,
              ),
            );

      await RestoreEvent(repository: repository, now: () => time)('parent');

      expect((await repository.getEvent('parent'))!.status, EventStatus.paused);
      expect(
        (await repository.getEvent('child'))!.status,
        EventStatus.completed,
      );
      expect(
        (await repository.getEvent('running'))!.status,
        EventStatus.running,
      );
      expect(await repository.getRunSegments('running'), hasLength(1));
    },
  );

  test('restored parent follows existing completion rules', () async {
    final repository = MemoryRepository([
      event('parent', EventStatus.completed),
      event('child', EventStatus.completed, parent: 'parent'),
    ]);
    final restore = RestoreEvent(repository: repository, now: () => time);
    await restore('parent');
    await CompleteEvent(repository: repository, now: () => time)('parent');
    expect(
      (await repository.getEvent('parent'))!.status,
      EventStatus.completed,
    );

    await restore('child');
    await expectLater(
      CompleteEvent(repository: repository, now: () => time)('parent'),
      throwsA(isA<DomainFailure>()),
    );
  });
}
