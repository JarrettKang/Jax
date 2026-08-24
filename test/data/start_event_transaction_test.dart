import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/run_segment.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';

void main() {
  test('atomically stores running state and open segment', () async {
    final db = await AppDatabase.inMemory();
    addTearDown(db.close);
    final repository = SqliteEventRepository(db);
    final time = DateTime.utc(2026);
    final pending = JaxEvent(
      id: 'event',
      name: '任务',
      status: EventStatus.pending,
      createdAt: time,
      updatedAt: time,
    );
    await repository.insertEvent(pending);
    final running = pending.copyWith(
      status: EventStatus.running,
      firstStartedAt: time,
    );
    final segment = RunSegment(
      id: 'segment',
      eventId: 'event',
      startedAt: time,
      createdAt: time,
    );
    await repository.startEvent(running, segment);
    expect((await repository.getEvent('event'))!.status, EventStatus.running);
    expect(await repository.getRunSegments('event'), [segment]);
  });
}
