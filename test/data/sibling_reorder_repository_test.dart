import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';

void main() {
  test('SQLite reorder persists after close and reopen', () async {
    final directory = await Directory.systemTemp.createTemp('jax-reorder-');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}${Platform.pathSeparator}jax.db';
    final time = DateTime.utc(2026, 8, 25, 8);
    var database = await AppDatabase.open(path);
    var repository = SqliteEventRepository(database);
    JaxEvent event(String id, int order) => JaxEvent(
      id: id,
      name: id,
      status: EventStatus.pending,
      sortOrder: order,
      createdAt: time,
      updatedAt: time,
    );
    await repository.insertEvent(event('a', 0));
    await repository.insertEvent(event('b', 1));
    await repository.insertEvent(event('c', 2));
    await repository.reorderSibling('c', 0);
    await database.close();

    database = await AppDatabase.open(path);
    addTearDown(database.close);
    repository = SqliteEventRepository(database);
    expect(
      (await repository.getOrderedTopLevelEvents()).map((item) => item.id),
      ['c', 'a', 'b'],
    );
  });

  test(
    'SQLite move and ordering update are atomic at the repository boundary',
    () async {
      final database = await AppDatabase.inMemory();
      addTearDown(database.close);
      final repository = SqliteEventRepository(database);
      final time = DateTime.utc(2026, 8, 25, 8);
      JaxEvent event(String id, {String? parent, int? order}) => JaxEvent(
        id: id,
        name: id,
        status: EventStatus.pending,
        parentEventId: parent,
        sortOrder: order,
        createdAt: time,
        updatedAt: time,
      );
      await repository.insertEvent(event('old-parent'));
      await repository.insertEvent(event('new-parent'));
      await repository.insertEvent(
        event('moved', parent: 'old-parent', order: 0),
      );
      await repository.insertEvent(
        event('existing', parent: 'new-parent', order: 0),
      );

      await repository.updateParent('moved', 'new-parent', time);

      expect(
        await repository.getParent('moved'),
        await repository.getEvent('new-parent'),
      );
      expect(
        (await repository.getDirectChildren('new-parent'))
            .map((item) => item.id),
        ['existing', 'moved'],
      );
      expect(await repository.getDirectChildren('old-parent'), isEmpty);
    },
  );
}
