import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/routine.dart';
import 'package:jax/core/services/routine_service.dart';
import 'package:jax/core/sync/sync_contract.dart';
import 'package:jax/core/sync/sync_mutation_plan.dart';
import 'package:jax/core/sync/sync_compare_engine.dart';
import 'package:jax/core/sync/resolved_sync_plan.dart';
import 'package:jax/core/sync/sync_plan_compiler.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';
import 'package:jax/data/sync/sqlite_sync_snapshot_adapter.dart';
import 'package:jax/data/sync/sqlite_sync_mutation_executor.dart';
import 'package:jax/ui/controllers/event_controller.dart';
import 'package:jax/core/entities/event_status.dart';

void main() {
  late AppDatabase db;
  late SqliteEventRepository repo;
  late RoutineService service;
  late DateTime now;
  var id = 0;
  setUp(() async {
    db = await AppDatabase.inMemory();
    repo = SqliteEventRepository(db);
    now = DateTime(2026, 9, 14, 10);
    id = 0;
    service = RoutineService(
      repository: repo,
      newId: () => 'id-${id++}',
      now: () => now,
    );
  });
  tearDown(() => db.close());
  Future<Routine> create(RoutineType type) async {
    await service.create(
      'Laundry',
      null,
      RoutineRecurrence.daily,
      0,
      type: type,
      timeRecommendation: type == RoutineType.scheduled
          ? const RoutineTimeRecommendation(
              startMinute: 540,
              endMinute: 630,
              latestEndMinute: 660,
            )
          : null,
    );
    return (await repo.getRoutines()).last;
  }

  for (final type in RoutineType.values) {
    test(
      '$type waiting closes timing and resumes same execution to total 15 minutes',
      () async {
        final r = await create(type);
        await service.start(r);
        final original = (await repo.getRoutineExecutions()).single;
        now = DateTime(2026, 9, 14, 10, 10);
        await service.wait(original);
        var e = (await repo.getRoutineExecutions()).single;
        expect(e.status, RoutineExecutionStatus.waiting);
        expect(
          (await repo.getRoutineRunSegments(e.id)).single.endedAt,
          now.toUtc(),
        );
        now = DateTime(2026, 9, 14, 10, 45);
        expect(
          (await repo.getRoutineRunSegments(e.id)).single.durationAt(now),
          const Duration(minutes: 10),
        );
        await service.start(r, execution: e);
        now = DateTime(2026, 9, 14, 10, 50);
        await service.complete((await repo.getRoutineExecutions()).single);
        e = (await repo.getRoutineExecutions()).single;
        expect(e.id, original.id);
        expect(e.status, RoutineExecutionStatus.completed);
        final segments = await repo.getRoutineRunSegments(e.id);
        expect(segments, hasLength(2));
        expect(
          segments.fold(Duration.zero, (a, s) => a + s.durationAt(now)),
          const Duration(minutes: 15),
        );
      },
    );
    test('$type waiting directly completes without adding segment', () async {
      final r = await create(type);
      await service.start(r);
      now = now.add(const Duration(minutes: 10));
      await service.wait((await repo.getRoutineExecutions()).single);
      final e = (await repo.getRoutineExecutions()).single;
      now = now.add(const Duration(minutes: 35));
      await service.complete(e);
      final segments = await repo.getRoutineRunSegments(e.id);
      expect(segments, hasLength(1));
      expect(segments.single.durationAt(now), const Duration(minutes: 10));
      await expectLater(service.start(r, execution: e), throwsA(anything));
    });
  }
  test('waiting survives expiry, multiple JaxDays and restart; resumes original and switches running Event', () async {
    final r = await create(RoutineType.scheduled);
    await service.start(r);
    now = now.add(const Duration(minutes: 10));
    await service.wait((await repo.getRoutineExecutions()).single);
    final original = (await repo.getRoutineExecutions()).single;
    now = DateTime(2026, 9, 17, 10);
    final c = EventController(
      repository: repo,
      newId: () => 'id-${id++}',
      now: () => now,
    );
    addTearDown(c.dispose);
    await c.load();
    expect(c.waitingRoutineExecutions.single.id, original.id);
    expect(c.homeRecommendations, isEmpty);
    expect(c.routineElapsed(r), const Duration(minutes: 10));
    await c.create('Other');
    final event = c.events.single;
    await c.start(event.id);
    expect(c.runningEvent, isNotNull);
    expect(await c.resumeWaitingRoutine(original), isNull);
    expect(c.runningEvent, isNull);
    expect((await repo.getEvent(event.id))!.status, EventStatus.paused);
    expect(c.runningRoutineExecution!.id, original.id);
    expect(c.runningRoutineExecution!.occurrenceDate, original.occurrenceDate);
    expect(await repo.getRoutineExecutions(), hasLength(1));
  });
  test('waiting round trips through Sync and direct completion on the other device', () async {
    final r = await create(RoutineType.scheduled);
    await service.start(r);
    now = now.add(const Duration(minutes: 10));
    await service.wait((await repo.getRoutineExecutions()).single);
    final otherDir = await Directory.systemTemp.createTemp('waiting-other-');
    addTearDown(() => otherDir.delete(recursive: true));
    final other = await AppDatabase.open('${otherDir.path}/other.db');
    addTearDown(other.close);
    final snapshot = await SqliteSyncSnapshotAdapter(db.database).read();
    final execution = snapshot.records.singleWhere(
      (r) => r.kind == SyncEntityKind.routineExecution,
    );
    expect(execution.payload['status'], 'waiting');
    expect(execution.payload.containsKey('isWaiting'), isFalse);
    const executor = SqliteSyncMutationExecutor();
    await executor.applyDatabase(other, [
      for (final r in snapshot.records) SyncMutation.upsertRecord(r),
      for (final l in snapshot.lists) SyncMutation.applyList(l),
    ]);
    final otherRepo = SqliteEventRepository(other);
    final e = (await otherRepo.getRoutineExecutions()).single;
    expect(e.status, RoutineExecutionStatus.waiting);
    now = now.add(const Duration(minutes: 35));
    await RoutineService(
      repository: otherRepo,
      newId: () => 'other',
      now: () => now,
    ).complete(e);
    final back = await SqliteSyncSnapshotAdapter(other.database).read();
    await executor.applyDatabase(db, [
      for (final r in back.records) SyncMutation.upsertRecord(r),
    ]);
    expect(
      (await repo.getRoutineExecutions()).single.status,
      RoutineExecutionStatus.completed,
    );
    expect(
      (await repo.getRoutineRunSegments(e.id)).single.durationAt(now),
      const Duration(minutes: 10),
    );
  });
  test('schema 23 migration adds only false waiting flag and keeps metadata and rows', () async {
    final dir = await Directory.systemTemp.createTemp('waiting-migration-');
    addTearDown(() => dir.delete(recursive: true));
    final file = '${dir.path}/old.db';
    var old = await AppDatabase.open(file);
    final oldRepo = SqliteEventRepository(old);
    await RoutineService(
      repository: oldRepo,
      newId: () => 'routine',
      now: () => now,
    ).create('Old', null, RoutineRecurrence.daily, 0);
    var sequence = 0;
    final oldService = RoutineService(
      repository: oldRepo,
      newId: () => 'exec-${sequence++}',
      now: () => now,
    );
    await oldService.start((await oldRepo.getRoutines()).single);
    now = now.add(const Duration(minutes: 10));
    await oldService.pause((await oldRepo.getRoutineExecutions()).single);
    final executions = await old.database.query('routine_executions');
    final segments = await old.database.query('routine_run_segments');
    final before = await old.database.query('routines');
    final metadata = await old.database.query('dataset_metadata');
    await old.database.execute(
      'ALTER TABLE routine_executions DROP COLUMN is_waiting',
    );
    await old.database.execute('PRAGMA user_version = 23');
    await old.close();
    old = await AppDatabase.open(file);
    expect(
      (await old.database.rawQuery('PRAGMA user_version')).single.values.single,
      24,
    );
    expect(await old.database.query('routines'), before);
    expect(await old.database.query('routine_executions'), executions);
    expect(await old.database.query('routine_run_segments'), segments);
    expect(await old.database.query('dataset_metadata'), metadata);
    expect(await old.database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    await old.close();
  });
  test(
    'protocol 10 baseline upgrades without altering records or metadata',
    () async {
      await create(RoutineType.scheduled);
      final snapshot = await SqliteSyncSnapshotAdapter(db.database).read();
      final json = snapshot.toJson()..['syncProtocolVersion'] = 10;
      final upgraded = SyncSnapshot.fromJson(json);
      expect(upgraded.protocolVersion, 11);
      expect(
        upgraded.records.map((r) => r.toJson()).toList(),
        snapshot.records.map((r) => r.toJson()).toList(),
      );
      expect(upgraded.datasetGeneration, snapshot.datasetGeneration);
    },
  );
  test(
    'waiting Sync compare/apply, conflict and rollback retain execution facts',
    () async {
      final r = await create(RoutineType.scheduled);
      await service.start(r);
      now = now.add(const Duration(minutes: 10));
      await service.pause((await repo.getRoutineExecutions()).single);
      final baseline = await SqliteSyncSnapshotAdapter(db.database).read();
      final otherDir = await Directory.systemTemp.createTemp('waiting-other-');
      addTearDown(() => otherDir.delete(recursive: true));
      final other = await AppDatabase.open('${otherDir.path}/other.db');
      addTearDown(other.close);
      await other.database.update('dataset_metadata', {
        'generation': baseline.datasetGeneration,
      });
      const executor = SqliteSyncMutationExecutor();
      await executor.applyDatabase(other, [
        for (final r in baseline.records) SyncMutation.upsertRecord(r),
        for (final l in baseline.lists) SyncMutation.applyList(l),
      ]);
      now = now.add(const Duration(minutes: 1));
      await service.start(
        r,
        execution: (await repo.getRoutineExecutions()).single,
      );
      now = now.add(const Duration(minutes: 1));
      await service.wait((await repo.getRoutineExecutions()).single);
      var w = await SqliteSyncSnapshotAdapter(db.database).read();
      var a = await SqliteSyncSnapshotAdapter(other.database).read();
      final preview = const SyncCompareEngine().compare(
        windows: w,
        android: a,
        baseline: baseline,
      );
      final plan = const SyncPlanCompiler().compile(
        resolved: ResolvedSyncPlan(preview: preview),
        windows: w,
        android: a,
        baseline: baseline,
      );
      await executor.applyDatabase(other, plan.androidOperations);
      expect(
        (await SqliteEventRepository(
          other,
        ).getRoutineExecutions()).single.status,
        RoutineExecutionStatus.waiting,
      );
      final synced = await SqliteSyncSnapshotAdapter(other.database).read();
      expect(synced.businessFingerprintSha256, w.businessFingerprintSha256);
      final record = w.records.singleWhere(
        (r) => r.kind == SyncEntityKind.routineExecution,
      );
      final invalid = SyncRecord(
        kind: record.kind,
        metadata: record.metadata,
        payload: {...record.payload, 'status': 'invalid-state'},
      );
      await expectLater(
        executor.applyDatabase(other, [SyncMutation.upsertRecord(invalid)]),
        throwsA(anything),
      );
      expect(
        (await SqliteSyncSnapshotAdapter(
          other.database,
        ).read()).businessFingerprintSha256,
        synced.businessFingerprintSha256,
      );
      now = now.add(const Duration(minutes: 1));
      await service.start(
        r,
        execution: (await repo.getRoutineExecutions()).single,
      );
      now = now.add(const Duration(minutes: 1));
      await service.pause((await repo.getRoutineExecutions()).single);
      final otherRepo = SqliteEventRepository(other);
      await RoutineService(
        repository: otherRepo,
        newId: () => 'other',
        now: () => now,
      ).complete((await otherRepo.getRoutineExecutions()).single);
      w = await SqliteSyncSnapshotAdapter(db.database).read();
      a = await SqliteSyncSnapshotAdapter(other.database).read();
      final conflicting = const SyncCompareEngine().compare(
        windows: w,
        android: a,
        baseline: synced,
      );
      expect(
        () => const SyncPlanCompiler().compile(
          resolved: ResolvedSyncPlan(preview: conflicting),
          windows: w,
          android: a,
          baseline: synced,
        ),
        throwsA(anything),
      );
    },
  );

  test('waiting releases running slot for another Routine and resume pauses that Routine', () async {
    final a = await create(RoutineType.onDemand);
    await service.start(a);
    now = now.add(const Duration(minutes: 1));
    await service.wait((await repo.getRoutineExecutions()).single);
    final waiting = (await repo.getRoutineExecutions()).single;
    final b = await create(RoutineType.onDemand);
    await service.start(b);
    expect((await repo.getRunningRoutineExecution())!.routineId, b.id);
    now = now.add(const Duration(minutes: 1));
    await service.start(a, execution: waiting);
    final executions = await repo.getRoutineExecutions();
    expect(
      executions.where((e) => e.status == RoutineExecutionStatus.running),
      hasLength(1),
    );
    expect(
      executions.firstWhere((e) => e.routineId == b.id).status,
      RoutineExecutionStatus.paused,
    );
    expect(
      (await repo.getAllRoutineRunSegments()).where((s) => s.endedAt == null),
      hasLength(1),
    );
  });
}
