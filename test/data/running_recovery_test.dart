import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/run_segment.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';

void main() {
  test(
    'reopen preserves running state and advances the open segment',
    () async {
      final directory = await Directory.systemTemp.createTemp('jax-running-');
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}${Platform.pathSeparator}jax.db';
      final startedAt = DateTime.utc(2026, 8, 25, 8);
      final reopenedAt = startedAt.add(const Duration(minutes: 37));

      var database = await AppDatabase.open(path);
      var repository = SqliteEventRepository(database);
      final pending = JaxEvent(
        id: 'event',
        name: '跨进程运行',
        status: EventStatus.pending,
        createdAt: startedAt,
        updatedAt: startedAt,
      );
      await repository.insertEvent(pending);
      await repository.startEvent(
        pending.copyWith(
          status: EventStatus.running,
          firstStartedAt: startedAt,
        ),
        RunSegment(
          id: 'open-segment',
          eventId: pending.id,
          startedAt: startedAt,
          createdAt: startedAt,
        ),
      );
      await database.close();

      database = await AppDatabase.open(path);
      addTearDown(database.close);
      repository = SqliteEventRepository(database);
      final restored = (await repository.getIncompleteEvents()).single;
      final segment = (await repository.getRunSegments(restored.id)).single;

      expect(restored.status, EventStatus.running);
      expect(segment.endedAt, isNull);
      expect(segment.durationAt(reopenedAt), const Duration(minutes: 37));
    },
  );
}
