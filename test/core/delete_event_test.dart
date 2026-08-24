import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/errors/domain_failure.dart';
import 'package:jax/core/use_cases/delete_event.dart';

import '../support/memory_repository.dart';

void main() {
  final time = DateTime.utc(2026, 8, 24);
  JaxEvent event(String id, EventStatus status) => JaxEvent(
    id: id,
    name: '同名',
    status: status,
    createdAt: time,
    updatedAt: time,
  );
  test('deletes pending by id without deleting duplicate names', () async {
    final repository = MemoryRepository([
      event('one', EventStatus.pending),
      event('two', EventStatus.pending),
    ]);
    await DeleteEvent(repository)("one");
    expect(repository.events.map((e) => e.id), ['two']);
  });
  test('rejects running and completed deletion', () async {
    for (final status in [EventStatus.running, EventStatus.completed]) {
      final repository = MemoryRepository([event('one', status)]);
      await expectLater(
        DeleteEvent(repository)('one'),
        throwsA(isA<DomainFailure>()),
      );
    }
  });
}
