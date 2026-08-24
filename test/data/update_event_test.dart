import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';

void main() {
  test('updates only the selected event id', () async {
    final database = await AppDatabase.inMemory();
    addTearDown(database.close);
    final repository = SqliteEventRepository(database);
    final time = DateTime.utc(2026, 8, 24, 12);
    for (final id in ['one', 'two']) {
      await repository.insertEvent(
        JaxEvent(
          id: id,
          name: '同名',
          status: EventStatus.pending,
          createdAt: time,
          updatedAt: time,
        ),
      );
    }

    final first = (await repository.getEvent('one'))!;
    await repository.updateEvent(first.copyWith(name: '已编辑'));
    final events = await repository.getIncompleteEvents();

    expect(events.singleWhere((event) => event.id == 'one').name, '已编辑');
    expect(events.singleWhere((event) => event.id == 'two').name, '同名');
  });
}
