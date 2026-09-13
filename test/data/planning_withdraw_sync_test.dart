import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/plan_item.dart';
import 'package:jax/core/entities/event_day_plan.dart';
import 'package:jax/core/entities/run_segment.dart';
import 'package:jax/core/errors/domain_failure.dart';
import 'package:jax/core/sync/resolved_sync_plan.dart';
import 'package:jax/core/sync/sync_compare_engine.dart';
import 'package:jax/core/sync/sync_contract.dart';
import 'package:jax/core/sync/sync_mutation_plan.dart';
import 'package:jax/core/sync/sync_plan_compiler.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';
import 'package:jax/data/repositories/sqlite_planning_repository.dart';
import 'package:jax/data/sync/sqlite_sync_mutation_executor.dart';
import 'package:jax/data/sync/sqlite_sync_snapshot_adapter.dart';

import '../support/world_map_fixture.dart';

void main() {
  test(
    'withdrawal on one peer conflicts with new execution on the other',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'jax-withdraw-conflict-',
      );
      final windows = await AppDatabase.open('${directory.path}/windows.db');
      final android = await AppDatabase.open('${directory.path}/android.db');
      addTearDown(() async {
        await windows.close();
        await android.close();
        await directory.delete(recursive: true);
      });
      await seedWorldMapFixture(windows);
      final now = DateTime.now().toUtc();
      await SqlitePlanningRepository(windows).dispatchPlanItems(
        eventIdsByPlanItemId: {'fixture-step-0': 'event'},
        dayKey: '2026-09-13',
        now: now,
      );
      final baseline = await SqliteSyncSnapshotAdapter(windows.database).read();
      await android.database.update('dataset_metadata', {
        'generation': baseline.datasetGeneration,
      });
      await const SqliteSyncMutationExecutor().applyDatabase(android, [
        for (final r in baseline.records) SyncMutation.upsertRecord(r),
        for (final l in baseline.lists) SyncMutation.applyList(l),
      ]);
      await SqlitePlanningRepository(android).withdrawPlanItem(
        planItemId: 'fixture-step-0',
        now: now.add(const Duration(seconds: 1)),
      );
      await SqliteEventRepository(windows).insertHistoricalRunSegment(
        RunSegment(
          id: 'reality',
          eventId: 'event',
          startedAt: now.subtract(const Duration(minutes: 2)),
          endedAt: now.subtract(const Duration(minutes: 1)),
          createdAt: now.add(const Duration(seconds: 2)),
        ),
      );
      final w = await SqliteSyncSnapshotAdapter(windows.database).read();
      final a = await SqliteSyncSnapshotAdapter(android.database).read();
      final preview = const SyncCompareEngine().compare(
        windows: w,
        android: a,
        baseline: baseline,
      );
      final resolved = ResolvedSyncPlan(preview: preview);
      expect(resolved.unresolvedKeys, isNotEmpty);
      expect(
        () => const SyncPlanCompiler().compile(
          resolved: resolved,
          windows: w,
          android: a,
          baseline: baseline,
        ),
        throwsA(isA<SyncPlanException>()),
      );
      expect(await windows.database.query('run_segments'), hasLength(1));
      expect(await windows.database.query('events'), hasLength(1));
    },
  );

  test('Windows/Android sync round-trip: draft dispatch, withdrawal, edit, redispatch and execution', () async {
    final directory = await Directory.systemTemp.createTemp(
      'jax-withdraw-sync-',
    );
    final windows = await AppDatabase.open('${directory.path}/windows.db');
    final android = await AppDatabase.open('${directory.path}/android.db');
    addTearDown(() async {
      await windows.close();
      await android.close();
      await directory.delete(recursive: true);
    });
    await seedWorldMapFixture(windows);
    final w = SqlitePlanningRepository(windows);
    final a = SqlitePlanningRepository(android);
    final now = DateTime.now().toUtc();
    await w.setPlanItemStatus('fixture-step-0', PlanItemStatus.draft, now);
    const executor = SqliteSyncMutationExecutor();
    Future<SyncSnapshot> snapshot(AppDatabase db) =>
        SqliteSyncSnapshotAdapter(db.database).read();
    final seed = await snapshot(windows);
    await android.database.update('dataset_metadata', {
      'generation': seed.datasetGeneration,
    });
    await executor.applyDatabase(android, [
      for (final record in seed.records) SyncMutation.upsertRecord(record),
      for (final list in seed.lists) SyncMutation.applyList(list),
    ]);
    var baseline = await snapshot(windows);
    expect(
      (await snapshot(android)).businessFingerprintSha256,
      baseline.businessFingerprintSha256,
    );

    Future<void> sync() async {
      final ws = await snapshot(windows);
      final an = await snapshot(android);
      final preview = const SyncCompareEngine().compare(
        windows: ws,
        android: an,
        baseline: baseline,
      );
      final resolved = ResolvedSyncPlan(preview: preview);
      expect(resolved.unresolvedKeys, isEmpty);
      final plan = const SyncPlanCompiler().compile(
        resolved: resolved,
        windows: ws,
        android: an,
        baseline: baseline,
      );
      await executor.applyDatabase(windows, plan.windowsOperations);
      await executor.applyDatabase(android, plan.androidOperations);
      baseline = await snapshot(windows);
      expect(
        (await snapshot(android)).businessFingerprintSha256,
        baseline.businessFingerprintSha256,
      );
      for (final db in [windows, android]) {
        expect(await db.database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      }
    }

    await w.dispatchPlanItems(
      eventIdsByPlanItemId: {'fixture-step-0': 'event-one'},
      dayKey: '2026-09-13',
      now: now,
    );
    await sync();
    expect(
      (await a.getPlanItems('fixture-plan')).first.status,
      PlanItemStatus.dispatched,
    );
    await SqliteEventRepository(android)
        .removeEventDayPlan('event-one', '2026-09-13');
    await sync();
    for (final db in [windows, android]) {
      expect(await db.database.query('event_day_plans'), isEmpty);
      expect(await db.database.query('events'), hasLength(1));
      expect(
        (await SqlitePlanningRepository(db).getPlanItems('fixture-plan'))
            .first
            .status,
        PlanItemStatus.dispatched,
      );
    }
    await SqliteEventRepository(windows).addEventDayPlan(
      EventDayPlan(
        eventId: 'event-one',
        dayKey: '2026-09-14',
        order: 0,
        createdAt: now,
      ),
    );
    await sync();
    await a.withdrawPlanItem(
      planItemId: 'fixture-step-0',
      now: now.add(const Duration(seconds: 1)),
    );
    await sync();
    for (final db in [windows, android]) {
      expect(await db.database.query('events'), isEmpty);
      expect(await db.database.query('event_day_plans'), isEmpty);
      expect(await db.database.query('sync_tombstones'), hasLength(3));
    }
    await w.editPlanItem(
      'fixture-step-0',
      title: '测试2e5',
      now: now.add(const Duration(seconds: 2)),
    );
    await w.dispatchPlanItems(
      eventIdsByPlanItemId: {'fixture-step-0': 'event-two'},
      dayKey: '2026-09-13',
      now: now.add(const Duration(seconds: 3)),
    );
    await sync();
    expect(
      (await SqliteEventRepository(android).getEvent('event-two'))!.name,
      '测试2e5',
    );
    await SqliteEventRepository(android).insertHistoricalRunSegment(
      RunSegment(
        id: 'manual',
        eventId: 'event-two',
        startedAt: now.subtract(const Duration(minutes: 2)),
        endedAt: now.subtract(const Duration(minutes: 1)),
        createdAt: now.add(const Duration(seconds: 4)),
      ),
    );
    await SqliteEventRepository(android).deleteClosedRunSegment('manual');
    await sync();
    for (final repository in [w, a]) {
      await expectLater(
        repository.withdrawPlanItem(planItemId: 'fixture-step-0', now: now),
        throwsA(isA<DomainFailure>()),
      );
    }
  });
}
