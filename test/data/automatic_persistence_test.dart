import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/run_segment.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';

void main() {
  test(
    'restores incomplete events, history, and segments after reopen',
    () async {
      final directory = await Directory.systemTemp.createTemp('jax-m10-');
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}${Platform.pathSeparator}jax.db';
      final time = DateTime.utc(2026, 8, 24, 12);

      var database = await AppDatabase.open(path);
      var repository = SqliteEventRepository(database);
      final kept = JaxEvent(
        id: 'kept',
        name: '原名称',
        status: EventStatus.pending,
        createdAt: time,
        updatedAt: time,
      );
      final removed = JaxEvent(
        id: 'removed',
        name: '删除我',
        status: EventStatus.pending,
        createdAt: time,
        updatedAt: time,
      );
      final completedPending = JaxEvent(
        id: 'completed',
        name: '已完成',
        status: EventStatus.pending,
        createdAt: time,
        updatedAt: time,
      );
      await repository.insertEvent(kept);
      await repository.updateEvent(kept.copyWith(name: '已编辑'));
      await repository.insertEvent(removed);
      await repository.deleteEvent(removed.id);
      await repository.insertEvent(completedPending);
      final segment = RunSegment(
        id: 'segment',
        eventId: completedPending.id,
        startedAt: time,
        createdAt: time,
      );
      await repository.startEvent(
        completedPending.copyWith(
          status: EventStatus.running,
          firstStartedAt: time,
        ),
        segment,
      );
      final endedAt = time.add(const Duration(minutes: 25));
      await repository.pauseEvent(
        completedPending.copyWith(
          status: EventStatus.paused,
          firstStartedAt: time,
          updatedAt: endedAt,
        ),
        segment.copyWith(endedAt: endedAt),
      );
      await repository.updateEvent(
        completedPending.copyWith(
          status: EventStatus.completed,
          firstStartedAt: time,
          completedAt: endedAt,
          updatedAt: endedAt,
        ),
      );
      await database.close();

      database = await AppDatabase.open(path);
      addTearDown(database.close);
      repository = SqliteEventRepository(database);

      expect((await repository.getIncompleteEvents()).single.name, '已编辑');
      expect(await repository.getEvent(removed.id), isNull);
      expect((await repository.getCompletedEvents()).single.id, 'completed');
      expect(
        (await repository.getRunSegments('completed')).single.endedAt,
        endedAt,
      );
    },
  );

  test(
    'failed transaction rolls back event state and segment insert',
    () async {
      final database = await AppDatabase.inMemory();
      addTearDown(database.close);
      final repository = SqliteEventRepository(database);
      final time = DateTime.utc(2026, 8, 24, 12);
      JaxEvent pending(String id) => JaxEvent(
        id: id,
        name: id,
        status: EventStatus.pending,
        createdAt: time,
        updatedAt: time,
      );
      final first = pending('first');
      final second = pending('second');
      await repository.insertEvent(first);
      await repository.insertEvent(second);
      final usedSegment = RunSegment(
        id: 'duplicate-segment',
        eventId: first.id,
        startedAt: time,
        createdAt: time,
      );
      await repository.startEvent(
        first.copyWith(status: EventStatus.running, firstStartedAt: time),
        usedSegment,
      );
      await repository.pauseEvent(
        first.copyWith(status: EventStatus.paused, firstStartedAt: time),
        usedSegment.copyWith(endedAt: time.add(const Duration(minutes: 1))),
      );

      await expectLater(
        repository.startEvent(
          second.copyWith(status: EventStatus.running, firstStartedAt: time),
          RunSegment(
            id: usedSegment.id,
            eventId: second.id,
            startedAt: time,
            createdAt: time,
          ),
        ),
        throwsA(anything),
      );

      expect(
        (await repository.getEvent(second.id))!.status,
        EventStatus.pending,
      );
      expect(await repository.getRunSegments(second.id), isEmpty);
    },
  );

  test('database reports the declared schema version', () async {
    final database = await AppDatabase.inMemory();
    addTearDown(database.close);
    final rows = await database.database.rawQuery('PRAGMA user_version');
    expect(rows.single['user_version'], AppDatabase.schemaVersion);
  });
}
