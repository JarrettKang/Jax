import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/use_cases/restore_event.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';

void main() {
  final time = DateTime.utc(2026, 8, 26, 8);
  JaxEvent completed(String id, {String? parent, int order = 0}) => JaxEvent(
    id: id,
    name: id,
    status: EventStatus.completed,
    parentEventId: parent,
    sortOrder: order,
    firstStartedAt: time,
    completedAt: time.add(const Duration(minutes: 5)),
    createdAt: time,
    updatedAt: time,
  );

  test(
    'SQLite atomically persists restored ancestor chain and facts',
    () async {
      final directory = await Directory.systemTemp.createTemp('jax-restore-');
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}${Platform.pathSeparator}jax.db';
      var database = await AppDatabase.open(path);
      var repository = SqliteEventRepository(database);
      await repository.insertEvent(completed('root', order: 0));
      await repository.insertEvent(completed('leaf', parent: 'root', order: 3));
      await database.database.insert('run_segments', {
        'id': 'segment',
        'event_id': 'leaf',
        'started_at_utc': time.millisecondsSinceEpoch,
        'ended_at_utc': time
            .add(const Duration(minutes: 5))
            .millisecondsSinceEpoch,
        'created_at_utc': time.millisecondsSinceEpoch,
      });

      await RestoreEvent(repository: repository, now: () => time)('leaf');
      await database.close();
      database = await AppDatabase.open(path);
      addTearDown(database.close);
      repository = SqliteEventRepository(database);

      for (final id in ['root', 'leaf']) {
        final restored = (await repository.getEvent(id))!;
        expect(restored.status, EventStatus.paused);
        expect(restored.completedAt, isNull);
      }
      expect((await repository.getEvent('leaf'))!.parentEventId, 'root');
      expect((await repository.getEvent('leaf'))!.sortOrder, 3);
      expect(await repository.getRunSegments('leaf'), hasLength(1));
    },
  );

  test(
    'SQLite restoration rolls back every ancestor on update failure',
    () async {
      final database = await AppDatabase.inMemory();
      addTearDown(database.close);
      final repository = SqliteEventRepository(database);
      await repository.insertEvent(completed('root'));
      await repository.insertEvent(completed('leaf', parent: 'root'));
      await database.database.execute('''CREATE TRIGGER reject_root_restore
      BEFORE UPDATE OF status ON events
      WHEN OLD.id = 'root' AND NEW.status = 'paused'
      BEGIN SELECT RAISE(ABORT, 'reject root'); END''');

      await expectLater(
        RestoreEvent(repository: repository, now: () => time)('leaf'),
        throwsA(anything),
      );
      expect(
        (await repository.getEvent('leaf'))!.status,
        EventStatus.completed,
      );
      expect(
        (await repository.getEvent('root'))!.status,
        EventStatus.completed,
      );
    },
  );
}
