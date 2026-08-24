import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/errors/domain_failure.dart';
import 'package:jax/core/use_cases/start_event.dart';

import '../support/memory_repository.dart';

void main() {
  test(
    'blocks starting a second event without changing either event',
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
      ]);
      final start = StartEvent(
        repository: repository,
        newId: () => 'segment',
        now: () => time,
      );
      await expectLater(
        start('pending'),
        throwsA(
          isA<DomainFailure>().having(
            (e) => e.message,
            'message',
            contains('暂停或完成'),
          ),
        ),
      );
      expect(
        (await repository.getEvent('running'))!.status,
        EventStatus.running,
      );
      expect(
        (await repository.getEvent('pending'))!.status,
        EventStatus.pending,
      );
      expect(repository.segments, isEmpty);
    },
  );
}
