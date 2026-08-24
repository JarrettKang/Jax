import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/use_cases/delete_history_record.dart';

import '../support/memory_repository.dart';

void main() {
  test('deletes completed history by id', () async {
    final time = DateTime.utc(2026);
    final repository = MemoryRepository([
      JaxEvent(
        id: 'done',
        name: '完成',
        status: EventStatus.completed,
        createdAt: time,
        updatedAt: time,
        firstStartedAt: time,
        completedAt: time,
      ),
    ]);
    await DeleteHistoryRecord(repository)('done');
    expect(repository.events, isEmpty);
  });
}
