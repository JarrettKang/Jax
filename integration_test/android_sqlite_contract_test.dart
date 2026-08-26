import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/run_segment.dart';
import 'package:jax/core/use_cases/restore_event.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';
import 'package:jax/data/services/sqlite_save_service.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android sqflite satisfies the Jax persistence contract', (
    tester,
  ) async {
    expect(Platform.isAndroid, isTrue, reason: 'Run this test on Android.');
    final databasePath = path.join(
      await getDatabasesPath(),
      'jax-contract-${DateTime.now().microsecondsSinceEpoch}.db',
    );
    addTearDown(() => deleteDatabase(databasePath));

    var database = await AppDatabase.openWithFactory(
      databasePath,
      databaseFactory,
    );
    var repository = SqliteEventRepository(database);
    final start = DateTime.utc(2026, 8, 25, 8);

    final foreignKeys = await database.database.rawQuery('PRAGMA foreign_keys');
    expect(foreignKeys.single.values.single, 1);

    JaxEvent pending(String id, String name) => JaxEvent(
      id: id,
      name: name,
      status: EventStatus.pending,
      createdAt: start,
      updatedAt: start,
    );

    final first = pending('first', '第一项');
    final second = pending('second', '第二项');
    final removed = pending('removed', '待删除');
    await repository.insertEvent(first);
    await repository.insertEvent(second);
    await repository.insertEvent(removed);
    await repository.updateEvent(first.copyWith(name: '第一项（已编辑）'));
    await repository.deleteEvent(removed.id);
    expect(await repository.getEvent(removed.id), isNull);

    final firstSegment = RunSegment(
      id: 'first-segment',
      eventId: first.id,
      startedAt: start,
      createdAt: start,
    );
    await repository.startEvent(
      first.copyWith(
        name: '第一项（已编辑）',
        status: EventStatus.running,
        firstStartedAt: start,
      ),
      firstSegment,
    );

    await expectLater(
      repository.startEvent(
        second.copyWith(status: EventStatus.running, firstStartedAt: start),
        RunSegment(
          id: 'blocked-segment',
          eventId: second.id,
          startedAt: start,
          createdAt: start,
        ),
      ),
      throwsStateError,
    );
    expect((await repository.getEvent(second.id))!.status, EventStatus.pending);
    expect(await repository.getRunSegments(second.id), isEmpty);

    final pausedAt = start.add(const Duration(minutes: 10));
    await repository.pauseEvent(
      (await repository.getEvent(first.id))!
          .copyWith(status: EventStatus.paused, updatedAt: pausedAt),
      firstSegment.copyWith(endedAt: pausedAt),
    );
    final resumedAt = pausedAt.add(const Duration(minutes: 5));
    final resumedSegment = RunSegment(
      id: 'resumed-segment',
      eventId: first.id,
      startedAt: resumedAt,
      createdAt: resumedAt,
    );
    await repository.startEvent(
      (await repository.getEvent(first.id))!
          .copyWith(status: EventStatus.running, updatedAt: resumedAt),
      resumedSegment,
    );
    final completedAt = resumedAt.add(const Duration(minutes: 5));
    await repository.pauseEvent(
      (await repository.getEvent(first.id))!.copyWith(
        status: EventStatus.completed,
        completedAt: completedAt,
        updatedAt: completedAt,
      ),
      resumedSegment.copyWith(endedAt: completedAt),
    );

    expect(await repository.getIncompleteEvents(), [second]);
    expect((await repository.getCompletedEvents()).single.id, first.id);
    expect(
      (await repository.getRunSegments(first.id)).fold<Duration>(
        Duration.zero,
        (total, segment) => total + segment.durationAt(completedAt),
      ),
      const Duration(minutes: 15),
    );

    await SqliteSaveService(database).flush();
    await database.close();
    database = await AppDatabase.openWithFactory(databasePath, databaseFactory);
    repository = SqliteEventRepository(database);

    expect((await repository.getEvent(second.id))!.status, EventStatus.pending);
    expect((await repository.getCompletedEvents()).single.name, '第一项（已编辑）');
    expect(await repository.getRunSegments(first.id), hasLength(2));

    await RestoreEvent(repository: repository, now: () => completedAt)(
      first.id,
    );
    final restored = (await repository.getEvent(first.id))!;
    expect(restored.status, EventStatus.paused);
    expect(restored.completedAt, isNull);
    expect(await repository.getRunSegments(first.id), hasLength(2));

    final rollback = pending('rollback', '事务回滚');
    await repository.insertEvent(rollback);
    await expectLater(
      repository.startEvent(
        rollback.copyWith(
          status: EventStatus.running,
          firstStartedAt: completedAt,
        ),
        RunSegment(
          id: firstSegment.id,
          eventId: rollback.id,
          startedAt: completedAt,
          createdAt: completedAt,
        ),
      ),
      throwsA(anything),
    );
    expect(
      (await repository.getEvent(rollback.id))!.status,
      EventStatus.pending,
    );
    expect(await repository.getRunSegments(rollback.id), isEmpty);

    await repository.deleteEvent(first.id);
    expect(await repository.getRunSegments(first.id), isEmpty);
    await database.close();
  });
}
