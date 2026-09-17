import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/event_day_plan.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/sync/sync_mutation_plan.dart';
import 'package:jax/core/sync/sync_compare_engine.dart';
import 'package:jax/core/sync/resolved_sync_plan.dart';
import 'package:jax/core/sync/sync_plan_compiler.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';
import 'package:jax/data/sync/sqlite_sync_snapshot_adapter.dart';
import 'package:jax/data/sync/sqlite_sync_mutation_executor.dart';
import 'package:jax/ui/controllers/event_controller.dart';

void main() {
  for (final reverse in [false, true]) {
    test(
      'defer preserves Event, refresh/carry-over and Sync reverse=$reverse',
      () async {
        final db = await AppDatabase.inMemory(),
            other = await AppDatabase.inMemory();
        addTearDown(db.close);
        addTearDown(other.close);
        final repo = SqliteEventRepository(db);
        var now = DateTime(2026, 9, 15, 14);
        final e = JaxEvent(
          id: 'e',
          name: 'Parcel',
          status: EventStatus.pending,
          createdAt: now.toUtc(),
          updatedAt: now.toUtc(),
        );
        await repo.insertEvent(e);
        await repo.addEventDayPlan(
          EventDayPlan(
            eventId: e.id,
            dayKey: '2026-09-14',
            order: 0,
            createdAt: now,
          ),
        );
        final c = EventController(
          newId: () => 'unused',
          repository: repo,
          now: () => now,
        );
        addTearDown(c.dispose);
        await c.load();
        expect(c.todayEvents, hasLength(1));
        final baseline = await SqliteSyncSnapshotAdapter(db.database).read();
        await other.database.update('dataset_metadata', {
          'generation': baseline.datasetGeneration,
        });
        const executor = SqliteSyncMutationExecutor();
        await executor.applyDatabase(other, [
          for (final r in baseline.records) SyncMutation.upsertRecord(r),
          for (final l in baseline.lists) SyncMutation.applyList(l),
        ]);
        expect(await c.removeFromToday(e.id), isNull);
        await c.load();
        expect(c.todayEvents, isEmpty);
        expect(await repo.getEvent(e.id), e);
        expect(await repo.getRunSegments(e.id), isEmpty);
        final source = await SqliteSyncSnapshotAdapter(db.database).read();
        final target = await SqliteSyncSnapshotAdapter(other.database).read();
        final w = reverse ? target : source, a = reverse ? source : target;
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
        await executor.applyDatabase(
          other,
          reverse ? plan.windowsOperations : plan.androidOperations,
        );
        expect(
          (await SqliteSyncSnapshotAdapter(
            other.database,
          ).read()).businessFingerprintSha256,
          source.businessFingerprintSha256,
        );
        final otherController = EventController(
          newId: () => 'unused',
          repository: SqliteEventRepository(other),
          now: () => now,
        );
        addTearDown(otherController.dispose);
        await otherController.load();
        expect(otherController.todayEvents, isEmpty);
        now = DateTime(2026, 9, 15, 23, 1);
        await c.load();
        expect(c.todayEvents, isEmpty);
        expect(await repo.getEvent(e.id), e);
        // Explicit re-add remains possible through the existing API.
        expect(await c.addToToday(e.id), isNull);
        expect(c.todayEvents, hasLength(1));
      },
    );
  }
}
