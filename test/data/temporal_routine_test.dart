import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/routine.dart';
import 'package:jax/core/services/routine_service.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';
import 'package:jax/ui/controllers/event_controller.dart';
import 'package:jax/data/sync/sqlite_sync_readiness.dart';
import 'package:jax/data/sync/sqlite_sync_snapshot_adapter.dart';
import 'package:jax/data/sync/sqlite_sync_mutation_executor.dart';
import 'package:jax/core/sync/sync_contract.dart';
import 'package:jax/core/sync/sync_mutation_plan.dart';

void main() {
  late Directory dir;
  late AppDatabase db;
  late SqliteEventRepository repo;
  late DateTime now;
  late RoutineService service;
  var id = 0;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('jax-temporal-');
    db = await AppDatabase.open('${dir.path}/local.db');
    repo = SqliteEventRepository(db);
    now = DateTime(2026, 9, 14, 22, 40);
    id = 0;
    service = RoutineService(
      repository: repo,
      newId: () => 'id-${id++}',
      now: () => now,
    );
    await service.create(
      'Night',
      null,
      RoutineRecurrence.selectedWeekdays,
      1,
      timeRecommendation: const RoutineTimeRecommendation(
        startMinute: 1350,
        endMinute: 30,
        latestEndMinute: 120,
      ),
    );
  });
  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });
  test('pending previous occurrence starts after boundary, pauses, resumes and completes original', () async {
    now = DateTime(2026, 9, 15, 0, 45);
    final controller = EventController(
      repository: repo,
      newId: () => 'id-${id++}',
      now: () => now,
    );
    addTearDown(controller.dispose);
    await controller.load();
    final routine = (await repo.getRoutines()).single;
    expect(controller.todayRoutines, hasLength(1));
    expect(controller.homeRecommendations, hasLength(1));
    expect(controller.temporalOccurrencesFor(routine), hasLength(1));
    expect(await controller.startRoutine(routine), isNull);
    final original = controller.executionFor(routine)!;
    expect(original.occurrenceDate, '2026-09-14');
    expect(
      (await repo.getRoutineRunSegments(original.id)).single.startedAt,
      now.toUtc(),
    );
    now = now.add(const Duration(minutes: 1));
    expect(await controller.pauseRoutine(routine), isNull);
    await controller.load();
    expect(controller.executionFor(routine)!.id, original.id);
    expect(await controller.startRoutine(routine), isNull);
    now = now.add(const Duration(minutes: 1));
    expect(await controller.completeRoutine(routine), isNull);
    expect(controller.homeRecommendations, isEmpty);
    expect(await repo.getRoutineExecution(routine.id, '2026-09-15'), isNull);
    expect(
      (await repo.getRoutineExecution(routine.id, '2026-09-14'))!.completedAt,
      now.toUtc(),
    );
  });
  test(
    'paused before 23:00 remains reachable after rollover and restart',
    () async {
      final r = (await repo.getRoutines()).single;
      await service.start(r);
      now = now.add(const Duration(minutes: 1));
      await service.pause((await repo.getRoutineExecutions()).single);
      now = DateTime(2026, 9, 15, 0, 45);
      final c = EventController(
        repository: repo,
        newId: () => 'id-${id++}',
        now: () => now,
      );
      addTearDown(c.dispose);
      await c.load();
      expect(c.executionFor(r)!.occurrenceDate, '2026-09-14');
      expect(await c.completeRoutine(r), isNull);
      expect(
        (await repo.getRoutineExecutions()).single.status,
        RoutineExecutionStatus.completed,
      );
    },
  );
  test(
    'expiry is derived, writes no facts and does not complete occurrence',
    () async {
      final r = (await repo.getRoutines()).single;
      await service.start(r);
      await service.pause((await repo.getRoutineExecutions()).single);
      now = DateTime(2026, 9, 15, 2, 1);
      final before = await db.database.query('routine_executions');
      final c = EventController(
        repository: repo,
        newId: () => 'id-${id++}',
        now: () => now,
      );
      addTearDown(c.dispose);
      await c.load();
      expect(c.homeRecommendations, isEmpty);
      expect(await db.database.query('routine_executions'), before);
    },
  );
  test(
    'daily next occurrence remains separate until its own next start',
    () async {
      var r = (await repo.getRoutines()).single.copyWith(
        recurrence: RoutineRecurrence.daily,
        weekdayMask: 0,
      );
      await repo.updateRoutine(r);
      await service.start(r);
      now = DateTime(2026, 9, 14, 23, 30);
      final c = EventController(
        repository: repo,
        newId: () => 'id-${id++}',
        now: () => now,
      );
      addTearDown(c.dispose);
      await c.load();
      expect(c.temporalOccurrencesFor(r).map((w) => w.occurrenceKey), [
        '2026-09-14',
        '2026-09-15',
      ]);
      expect(c.executionForOccurrence(r, '2026-09-15'), isNull);
      final old = c.executionFor(r)!;
      await c.completeRoutine(r);
      expect(c.homeRecommendations, isEmpty);
      now = DateTime(2026, 9, 15, 22, 30);
      await c.load();
      expect(c.homeRecommendations, hasLength(1));
      expect(await c.startRoutine(r), isNull);
      final next = c.executionFor(r)!;
      expect(next.id, isNot(old.id));
      expect(next.occurrenceDate, '2026-09-15');
      expect(
        (await repo.getRoutineRunSegments(next.id)).single.startedAt,
        now.toUtc(),
      );
    },
  );
  test('repository and SQL reject invalid triples without writes', () async {
    final r = (await repo.getRoutines()).single;
    final before = await db.database.query('routines');
    await expectLater(
      repo.updateRoutine(
        r.copyWith(
          timeRecommendation: const RoutineTimeRecommendation(
            startMinute: 660,
            endMinute: 1080,
            latestEndMinute: 840,
          ),
        ),
      ),
      throwsA(anything),
    );
    await expectLater(
      db.database.update('routines', {
        'time_recommendation_latest_end_minute': null,
      }),
      throwsA(anything),
    );
    expect(await db.database.query('routines'), before);
  });
  test('schema 22 migration copies end, preserves metadata/execution and reopens safely', () async {
    await service.start((await repo.getRoutines()).single);
    final legacyJson = (await SqliteSyncSnapshotAdapter(
      db.database,
    ).read()).toJson();
    legacyJson['syncProtocolVersion'] = 9;
    legacyJson['schemaVersion'] = 22;
    for (final record in legacyJson['records']! as List) {
      if (record['kind'] == 'routine') {
        (record['payload'] as Map).remove('timeRecommendationLatestEndMinute');
      }
    }
    final legacyBaseline = SyncSnapshot.fromJson(legacyJson);
    await db.database.execute('DROP TRIGGER routine_temporal_insert');
    await db.database.execute('DROP TRIGGER routine_temporal_update');
    await db.database.execute(
      'ALTER TABLE routines DROP COLUMN time_recommendation_latest_end_minute',
    );
    await db.database.execute('PRAGMA user_version = 22');
    final before = await db.database.query('routines');
    final executions = await db.database.query('routine_executions');
    await db.close();
    db = await AppDatabase.open('${dir.path}/local.db');
    expect(await db.database.query('routines'), [
      for (final r in before)
        {
          ...r,
          'time_recommendation_latest_end_minute':
              r['time_recommendation_end_minute'],
        },
    ]);
    expect(await db.database.query('routine_executions'), executions);
    expect(
      (await SqliteSyncSnapshotAdapter(
        db.database,
      ).read()).businessFingerprintSha256,
      legacyBaseline.businessFingerprintSha256,
    );

    expect(await SqliteSyncReadiness(db).validate(), isEmpty);
    await db.close();
    db = await AppDatabase.open('${dir.path}/local.db');
    expect(await db.database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });
  test(
    'Sync roundtrip and protocol 9 migration preserve endpoints and tombstones',
    () async {
      final other = await AppDatabase.open('${dir.path}/other.db');
      addTearDown(other.close);
      final snapshot = await SqliteSyncSnapshotAdapter(db.database).read();
      await const SqliteSyncMutationExecutor().applyDatabase(other, [
        for (final r in snapshot.records) SyncMutation.upsertRecord(r),
        for (final l in snapshot.lists) SyncMutation.applyList(l),
      ]);
      final r = (await SqliteEventRepository(other).getRoutines()).single;
      expect(r.timeRecommendation!.latestEndMinute, 120);
      final old = jsonDecode(snapshot.toJsonString()) as Map<String, dynamic>;
      old['syncProtocolVersion'] = 9;
      for (final record in old['records'] as List) {
        if (record['kind'] == 'routine') {
          (record['payload'] as Map).remove(
            'timeRecommendationLatestEndMinute',
          );
        }
      }
      final upgraded = SyncSnapshot.fromJson(old);
      expect(upgraded.protocolVersion, syncProtocolVersion);
      expect(
        upgraded.records
            .where((r) => r.kind == SyncEntityKind.routine)
            .single
            .payload['timeRecommendationLatestEndMinute'],
        30,
      );
      expect(await SqliteSyncReadiness(other).validate(), isEmpty);
    },
  );
}
