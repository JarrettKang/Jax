import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';

void main() {
  test('deleting completed event cascades to run segments', () async {
    final db = await AppDatabase.inMemory();
    addTearDown(db.close);
    final repository = SqliteEventRepository(db);
    final time = DateTime.utc(2026);
    final event = JaxEvent(
      id: 'done',
      name: '完成',
      status: EventStatus.completed,
      createdAt: time,
      updatedAt: time,
      firstStartedAt: time,
      completedAt: time,
    );
    await repository.insertEvent(event);
    await db.database.insert('run_segments', {
      'id': 'segment',
      'event_id': 'done',
      'started_at_utc': time.millisecondsSinceEpoch,
      'ended_at_utc': time.millisecondsSinceEpoch,
      'created_at_utc': time.millisecondsSinceEpoch,
    });
    await repository.deleteEvent('done');
    expect(await repository.getRunSegments('done'), isEmpty);
  });
}
