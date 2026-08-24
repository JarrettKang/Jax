import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/run_segment.dart';
import 'package:jax/core/use_cases/prepare_for_shutdown.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';
import 'package:jax/data/services/sqlite_save_service.dart';

void main() {
  test('reopen restores paused state and excludes closed time', () async {
    final directory = await Directory.systemTemp.createTemp('jax-close-');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}${Platform.pathSeparator}jax.db';
    final startedAt = DateTime.utc(2026, 8, 24, 12);
    final closedAt = startedAt.add(const Duration(minutes: 20));
    final reopenedAt = closedAt.add(const Duration(hours: 8));
    var database = await AppDatabase.open(path);
    var repository = SqliteEventRepository(database);
    final pending = JaxEvent(
      id: 'event',
      name: '跨重启任务',
      status: EventStatus.pending,
      createdAt: startedAt,
      updatedAt: startedAt,
    );
    await repository.insertEvent(pending);
    await repository.startEvent(
      pending.copyWith(status: EventStatus.running, firstStartedAt: startedAt),
      RunSegment(
        id: 'segment',
        eventId: pending.id,
        startedAt: startedAt,
        createdAt: startedAt,
      ),
    );
    await PrepareForShutdown(
      repository: repository,
      saveService: SqliteSaveService(database),
      now: () => closedAt,
    )();
    await database.close();

    database = await AppDatabase.open(path);
    addTearDown(database.close);
    repository = SqliteEventRepository(database);
    final restored = (await repository.getIncompleteEvents()).single;
    final segment = (await repository.getRunSegments(restored.id)).single;

    expect(restored.status, EventStatus.paused);
    expect(segment.durationAt(reopenedAt), const Duration(minutes: 20));
  });
}
