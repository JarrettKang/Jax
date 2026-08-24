import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';

void main() {
  test('deletes one event by id', () async {
    final db = await AppDatabase.inMemory();
    addTearDown(db.close);
    final repository = SqliteEventRepository(db);
    final time = DateTime.utc(2026);
    await repository.insertEvent(
      JaxEvent(
        id: 'one',
        name: '任务',
        status: EventStatus.pending,
        createdAt: time,
        updatedAt: time,
      ),
    );
    await repository.deleteEvent('one');
    expect(await repository.getEvent('one'), isNull);
  });
}
