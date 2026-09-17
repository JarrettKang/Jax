import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/plan.dart';
import 'package:jax/core/entities/routine.dart';
import 'package:jax/core/services/routine_service.dart';
import 'package:jax/core/use_cases/complete_event.dart';
import 'package:jax/core/sync/sync_mutation_plan.dart';
import 'package:jax/core/sync/sync_compare_engine.dart';
import 'package:jax/core/sync/resolved_sync_plan.dart';
import 'package:jax/core/sync/sync_plan_compiler.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';
import 'package:jax/data/repositories/sqlite_planning_repository.dart';
import 'package:jax/data/repositories/sqlite_world_node_repository.dart';
import 'package:jax/data/sync/sqlite_sync_snapshot_adapter.dart';
import 'package:jax/data/sync/sqlite_sync_mutation_executor.dart';
import 'package:jax/ui/controllers/event_controller.dart';

import '../support/world_map_fixture.dart';

void main() {
  for (final kind in ['standalone', 'planned', 'scheduled', 'onDemand']) {
    for (final reverse in [false, true]) {
      test(
        '$kind paused completion preserves duration and Sync reverse=$reverse',
        () async {
          final db = await AppDatabase.inMemory(),
              other = await AppDatabase.inMemory();
          addTearDown(db.close);
          addTearDown(other.close);
          final repo = SqliteEventRepository(db);
          var now = DateTime(2026, 9, 15, 10), seq = 0;
          final c = EventController(
            repository: repo,
            now: () => now,
            newId: () => 'id-${seq++}',
          );
          addTearDown(c.dispose);
          Routine? routine;
          final isRoutine = kind == 'scheduled' || kind == 'onDemand';
          if (isRoutine) {
            final service = RoutineService(
              repository: repo,
              now: () => now,
              newId: () => 'id-${seq++}',
            );
            await service.create(
              'Routine',
              null,
              RoutineRecurrence.daily,
              0,
              type: kind == 'scheduled'
                  ? RoutineType.scheduled
                  : RoutineType.onDemand,
              timeRecommendation: kind == 'scheduled'
                  ? const RoutineTimeRecommendation(
                      startMinute: 600,
                      endMinute: 630,
                      latestEndMinute: 640,
                    )
                  : null,
            );
            routine = (await repo.getRoutines()).single;
            await service.start(routine);
          } else {
            if (kind == 'planned') {
              await seedWorldMapFixture(db);
              await SqlitePlanningRepository(db).dispatchPlanItems(
                eventIdsByPlanItemId: {'fixture-step-0': 'e'},
                dayKey: '2026-09-15',
                now: now,
              );
            } else {
              await repo.insertEvent(
                JaxEvent(
                  id: 'e',
                  name: 'Event',
                  status: EventStatus.pending,
                  createdAt: now,
                  updatedAt: now,
                ),
              );
            }
            await c.load();
            expect(await c.start('e'), isNull);
          }
          await c.load();
          now = DateTime(2026, 9, 15, 10, 30);
          expect(
            isRoutine ? await c.pauseRoutine(routine!) : await c.pause('e'),
            isNull,
          );
          if (kind == 'planned') {
            await SqlitePlanningRepository(db)
                .setPlanStatus('fixture-plan', PlanStatus.ended, now);
            await SqliteWorldNodeRepository(db)
                .setWorldNodeFocus(mapNodeId(3), false, now);
          }
          final segmentTable = isRoutine
              ? 'routine_run_segments'
              : 'run_segments';
          final beforeSegments = await db.database.query(segmentTable);
          final baseline = await SqliteSyncSnapshotAdapter(db.database).read();
          await other.database.update('dataset_metadata', {
            'generation': baseline.datasetGeneration,
          });
          const executor = SqliteSyncMutationExecutor();
          await executor.applyDatabase(other, [
            for (final r in baseline.records) SyncMutation.upsertRecord(r),
            for (final l in baseline.lists) SyncMutation.applyList(l),
          ]);
          now = DateTime(2026, 9, 15, 11);
          if (isRoutine) {
            expect(
              await c.completeRoutineExecution(
                (await repo.getRoutineExecutions()).single,
              ),
              isNull,
            );
            expect(
              (await repo.getRoutineExecutions()).single.completedAt,
              now.toUtc(),
            );
            expect(
              (await repo.getAllRoutineRunSegments()).single.durationAt(now),
              const Duration(minutes: 30),
            );
            expect(c.pausedRoutineExecutions, isEmpty);
            expect(
              c.homeRecommendations.where(
                (x) => x.candidate.routine?.id == routine!.id,
              ),
              isEmpty,
            );
          } else {
            final result = await CompleteEvent(
              repository: repo,
              now: () => now,
            )('e');
            expect(result.duration, const Duration(minutes: 30));
            expect(result.event.completedAt, now.toUtc());
            if (kind == 'planned') {
              expect(
                (await db.database.query(
                  'plan_items',
                  where: 'id = ?',
                  whereArgs: ['fixture-step-0'],
                )).single['status'],
                'done',
              );
            }
            expect(await c.complete('e'), isNotNull);
          }
          expect(await db.database.query(segmentTable), beforeSegments);
          final source = await SqliteSyncSnapshotAdapter(db.database).read(),
              target = await SqliteSyncSnapshotAdapter(other.database).read();
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
          expect(await other.database.query(segmentTable), beforeSegments);
        },
      );
    }
  }

  test('zero-segment paused Event completes; corrupt open and stale transaction reject', () async {
    final db = await AppDatabase.inMemory();
    addTearDown(db.close);
    final repo = SqliteEventRepository(db);
    final now = DateTime.utc(2026, 9, 15, 11);
    final e = JaxEvent(
      id: 'e',
      name: 'Legacy paused',
      status: EventStatus.paused,
      createdAt: now,
      updatedAt: now,
    );
    await repo.insertEvent(e);
    final result = await CompleteEvent(repository: repo, now: () => now)('e');
    expect(result.duration, Duration.zero);
    expect(await repo.getRunSegments('e'), isEmpty);
    await expectLater(
      repo.updateEvent(
        e.copyWith(status: EventStatus.completed),
        expectedPaused: e,
      ),
      throwsA(anything),
    );
    await repo.updateEvent(e);
    await db.database.insert('run_segments', {
      'id': 'open',
      'event_id': 'e',
      'started_at_utc': now.millisecondsSinceEpoch,
      'created_at_utc': now.millisecondsSinceEpoch,
      'updated_at_utc': now.millisecondsSinceEpoch,
    });
    await expectLater(
      CompleteEvent(repository: repo, now: () => now)('e'),
      throwsA(anything),
    );
    expect((await repo.getEvent('e'))!.status, EventStatus.paused);
    await expectLater(
      repo.updateEvent(
        e.copyWith(status: EventStatus.completed),
        expectedPaused: e,
      ),
      throwsA(anything),
    );
    expect((await repo.getRunSegments('e')).single.endedAt, isNull);
  });

  test('legacy paused Routine completes without segments; stale and corrupt writes reject', () async {
    final db = await AppDatabase.inMemory();
    addTearDown(db.close);
    final repo = SqliteEventRepository(db);
    final now = DateTime.utc(2026, 9, 15, 11);
    final service = RoutineService(
      repository: repo,
      newId: () => 'routine',
      now: () => now,
    );
    await service.create('Routine', null, RoutineRecurrence.daily, 0);
    final r = (await repo.getRoutines()).single;
    await db.database.insert('routine_executions', {
      'id': 'execution',
      'routine_id': r.id,
      'occurrence_date': '2026-09-15',
      'status': 'paused',
      'created_at_utc': now.millisecondsSinceEpoch,
      'updated_at_utc': now.millisecondsSinceEpoch,
    });
    final e = (await repo.getRoutineExecutions()).single;
    await service.complete(e);
    expect(
      (await repo.getRoutineExecutions()).single.status,
      RoutineExecutionStatus.completed,
    );
    expect(await repo.getAllRoutineRunSegments(), isEmpty);
    await expectLater(service.complete(e), throwsA(anything));
    await expectLater(
      repo.updateRoutineExecutionOnly(
        e.copyWith(status: RoutineExecutionStatus.completed),
        expectedPaused: e,
      ),
      throwsA(anything),
    );
    await repo.updateRoutineExecutionOnly(e);
    await db.database.insert('routine_run_segments', {
      'id': 'bad-open',
      'routine_execution_id': e.id,
      'started_at_utc': now.millisecondsSinceEpoch,
      'created_at_utc': now.millisecondsSinceEpoch,
      'updated_at_utc': now.millisecondsSinceEpoch,
    });
    await expectLater(service.complete(e), throwsA(anything));
    expect(
      (await repo.getRoutineExecutions()).single.status,
      RoutineExecutionStatus.paused,
    );
  });

  test(
    'paused completion rolls back Event when linked PlanItem update fails',
    () async {
      final db = await AppDatabase.inMemory();
      addTearDown(db.close);
      await seedWorldMapFixture(db);
      final repo = SqliteEventRepository(db);
      var now = DateTime(2026, 9, 15, 10), seq = 0;
      final c = EventController(
        repository: repo,
        now: () => now,
        newId: () => 's-${seq++}',
      );
      addTearDown(c.dispose);
      await SqlitePlanningRepository(db).dispatchPlanItems(
        eventIdsByPlanItemId: {'fixture-step-0': 'e'},
        dayKey: '2026-09-15',
        now: now,
      );
      await c.load();
      await c.start('e');
      now = now.add(const Duration(minutes: 30));
      await c.pause('e');
      final before = await db.database.query('run_segments');
      await db.database.execute(
        "CREATE TRIGGER reject_done BEFORE UPDATE ON plan_items BEGIN SELECT RAISE(ABORT, 'injected'); END",
      );
      now = now.add(const Duration(minutes: 30));
      expect(await c.complete('e'), isNotNull);
      expect((await repo.getEvent('e'))!.status, EventStatus.paused);
      expect(await db.database.query('run_segments'), before);
    },
  );
}
