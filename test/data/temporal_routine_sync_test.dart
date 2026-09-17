import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/routine.dart';
import 'package:jax/core/sync/sync_contract.dart';
import 'package:jax/core/sync/sync_compare_engine.dart';
import 'package:jax/core/sync/resolved_sync_plan.dart';
import 'package:jax/core/sync/sync_mutation_plan.dart';
import 'package:jax/core/sync/sync_plan_compiler.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';
import 'package:jax/data/sync/sqlite_sync_mutation_executor.dart';
import 'package:jax/data/sync/sqlite_sync_snapshot_adapter.dart';

void main() {
  late Directory dir;
  late AppDatabase windows, android;
  late SyncSnapshot baseline;
  final now = DateTime(2026, 9, 14);
  const executor = SqliteSyncMutationExecutor();
  Future<SyncSnapshot> snapshot(AppDatabase db) =>
      SqliteSyncSnapshotAdapter(db.database).read();
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('jax-temporal-sync-');
    windows = await AppDatabase.open('${dir.path}/windows.db');
    android = await AppDatabase.open('${dir.path}/android.db');
    await SqliteEventRepository(windows).insertRoutine(
      Routine(
        id: 'night',
        name: 'Night',
        recurrence: RoutineRecurrence.daily,
        weekdayMask: 0,
        isActive: true,
        sortOrder: 0,
        createdAt: now,
        updatedAt: now,
        timeRecommendation: const RoutineTimeRecommendation(
          startMinute: 1350,
          endMinute: 30,
          latestEndMinute: 120,
        ),
      ),
    );
    baseline = await snapshot(windows);
    await android.database.update('dataset_metadata', {
      'generation': baseline.datasetGeneration,
    });
    await executor.applyDatabase(android, [
      for (final r in baseline.records) SyncMutation.upsertRecord(r),
      for (final l in baseline.lists) SyncMutation.applyList(l),
    ]);
  });
  tearDown(() async {
    await windows.close();
    await android.close();
    await dir.delete(recursive: true);
  });
  Future<SyncMutationPlan> compile() async {
    final w = await snapshot(windows), a = await snapshot(android);
    final preview = const SyncCompareEngine().compare(
      windows: w,
      android: a,
      baseline: baseline,
    );
    return const SyncPlanCompiler().compile(
      resolved: ResolvedSyncPlan(preview: preview),
      windows: w,
      android: a,
      baseline: baseline,
    );
  }

  Future<void> sync() async {
    final plan = await compile();
    await executor.applyDatabase(windows, plan.windowsOperations);
    await executor.applyDatabase(android, plan.androidOperations);
    baseline = await snapshot(windows);
    expect(
      (await snapshot(android)).businessFingerprintSha256,
      baseline.businessFingerprintSha256,
    );
  }

  Future<void> change(AppDatabase db, int latest) async {
    final repo = SqliteEventRepository(db);
    await repo.updateRoutine(
      (await repo.getRoutines()).single.copyWith(
        updatedAt: now.add(Duration(minutes: latest)),
        timeRecommendation: RoutineTimeRecommendation(
          startMinute: 1350,
          endMinute: 30,
          latestEndMinute: latest,
        ),
      ),
    );
  }

  test('all three endpoints sync both directions and deletion preserves tombstones', () async {
    await change(windows, 180);
    await sync();
    expect(
      (await SqliteEventRepository(
        android,
      ).getRoutines()).single.timeRecommendation!.latestEndMinute,
      180,
    );
    await change(android, 210);
    await sync();
    expect(
      (await SqliteEventRepository(
        windows,
      ).getRoutines()).single.timeRecommendation!.latestEndMinute,
      210,
    );
    await android.database.delete(
      'routines',
      where: 'id = ?',
      whereArgs: ['night'],
    );
    await sync();
    expect(await windows.database.query('routines'), isEmpty);
    expect(await windows.database.query('sync_tombstones'), isNotEmpty);
  });
  test(
    'concurrent endpoint edits require explicit conflict resolution',
    () async {
      await change(windows, 150);
      await change(android, 180);
      await expectLater(compile(), throwsA(anything));
    },
  );
  test(
    'invalid raw Sync apply is transactional and preserves original records',
    () async {
      final record = baseline.records.singleWhere(
        (r) => r.kind == SyncEntityKind.routine,
      );
      final before = await android.database.query('routines');
      final invalid = SyncRecord(
        kind: record.kind,
        metadata: record.metadata,
        payload: {
          ...record.payload,
          'timeRecommendationStartMinute': 660,
          'timeRecommendationEndMinute': 1080,
          'timeRecommendationLatestEndMinute': 840,
        },
      );
      await expectLater(
        executor.applyDatabase(android, [SyncMutation.upsertRecord(invalid)]),
        throwsA(anything),
      );
      expect(await android.database.query('routines'), before);
      expect(await android.database.query('sync_tombstones'), isEmpty);
    },
  );
  test('old peer database is rejected until migration', () async {
    await android.database.execute('PRAGMA user_version = 22');
    await expectLater(snapshot(android), throwsStateError);
  });
}
