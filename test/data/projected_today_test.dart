import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/plan.dart';
import 'package:jax/core/entities/routine.dart';
import 'package:jax/core/services/routine_service.dart';
import 'package:jax/core/entities/plan_item.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/world_node.dart';
import 'package:jax/core/use_cases/complete_event.dart';
import 'package:jax/core/use_cases/restore_event.dart';
import 'package:jax/core/sync/sync_mutation_plan.dart';
import 'package:jax/core/sync/sync_contract.dart';
import 'package:jax/core/sync/sync_compare_engine.dart';
import 'package:jax/core/sync/resolved_sync_plan.dart';
import 'package:jax/core/sync/sync_plan_compiler.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/repositories/sqlite_planning_repository.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';
import 'package:jax/data/repositories/sqlite_world_node_repository.dart';
import 'package:jax/data/sync/sqlite_sync_snapshot_adapter.dart';
import 'package:jax/data/sync/sqlite_sync_mutation_executor.dart';
import 'package:jax/ui/controllers/planning_controller.dart';
import 'package:jax/ui/controllers/event_controller.dart';

void main() {
  late Directory directory;
  late AppDatabase db;
  late SqlitePlanningRepository repo;
  late SqliteEventRepository events;
  late PlanningController planning;
  late EventController execution;
  final now = DateTime.utc(2026, 9, 14, 2);
  const nodeId = '00000000-0000-4000-8000-000000000001';
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('jax-projected-');
    db = await AppDatabase.open('${directory.path}/windows.db');
    repo = SqlitePlanningRepository(db);
    events = SqliteEventRepository(db);
    final worlds = SqliteWorldNodeRepository(db);
    await worlds.insertWorldNode(
      WorldNode(
        id: nodeId,
        name: 'World',
        status: WorldNodeStatus.inProgress,
        isFocused: true,
        sortOrder: 0,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await repo.createPlan(id: 'plan', worldNodeId: nodeId, now: now);
    await repo.createPlanItem(
      id: 'one',
      planId: 'plan',
      title: 'One',
      note: 'Note',
      now: now,
    );
    await repo.createPlanItem(
      id: 'two',
      planId: 'plan',
      title: 'Two',
      now: now,
    );
    var id = 0;
    execution = EventController(
      repository: events,
      newId: () => 'exec-${id++}',
      now: () => now,
    );
    planning = PlanningController(
      planningRepository: repo,
      worldNodeRepository: worlds,
      eventRepository: events,
      newId: () => 'id-${id++}',
      now: () => now,
      onExecutionChanged: execution.load,
    );
    await execution.load();
    await planning.load();
  });
  tearDown(() async {
    planning.dispose();
    execution.dispose();
    await db.close();
    await directory.delete(recursive: true);
  });
  Future<void> emptyExecution() async {
    for (final table in ['events', 'event_day_plans', 'run_segments']) {
      expect(await db.database.query(table), isEmpty, reason: table);
    }
  }

  Future<dynamic> start(String item, String event, String segment) =>
      repo.startPlanItem(
        planItemId: item,
        eventId: event,
        segmentId: segment,
        dayKey: '2026-09-14',
        now: now,
      );

  test(
    'default next and dynamic projection never persist Today records',
    () async {
      expect(planning.projectedTodayItems.map((i) => i.id), ['one', 'two']);
      expect(
        planning.itemsFor('plan').every((i) => i.status == PlanItemStatus.next),
        isTrue,
      );
      await emptyExecution();
      await planning.editItem(
        planning.itemsFor('plan').first,
        'Renamed',
        'Note',
      );
      expect(planning.projectedTodayItems.first.title, 'Renamed');
      await planning.setItemStatus(
        planning.itemsFor('plan').first,
        PlanItemStatus.dropped,
      );
      expect(planning.projectedTodayItems.map((i) => i.id), ['two']);
      await planning.deleteItem(planning.itemsFor('plan').last);
      expect(planning.projectedTodayItems, isEmpty);
      await emptyExecution();
    },
  );
  test('focus and ended control only unexecuted projections', () async {
    await db.database.update('world_nodes', {'is_focused': 0});
    await planning.load();
    expect(planning.projectedTodayItems, isEmpty);
    await expectLater(start('one', 'e', 's'), throwsA(anything));
    await emptyExecution();
    await db.database.update('world_nodes', {'is_focused': 1});
    await planning.load();
    expect(planning.projectedTodayItems, hasLength(2));
    await start('one', 'e', 's');
    await db.database.update('world_nodes', {'is_focused': 0});
    await execution.load();
    expect(execution.todayEvents.single.id, 'e');
    await db.database.update('world_nodes', {'is_focused': 1});
    await repo.setPlanStatus('plan', PlanStatus.ended, now);
    await planning.load();
    expect(planning.projectedTodayItems, isEmpty);
    await expectLater(start('two', 'e2', 's2'), throwsA(anything));
    expect((await events.getEvent('e'))!.status, EventStatus.running);
    expect((await repo.getPlanItems('plan')).last.status, PlanItemStatus.next);
  });
  test(
    'start atomically creates execution; completed and restore keep linkage',
    () async {
      final event = await planning.startPlanItem('one');
      expect(event.status, EventStatus.running);
      expect(event.sourcePlanItemId, 'one');
      expect(event.firstStartedAt, now);
      expect(planning.projectedTodayItems.map((i) => i.id), ['two']);
      expect(execution.todayEvents.single.id, event.id);
      expect((await events.getRunSegments(event.id)).single.endedAt, isNull);
      await expectLater(
        start('one', 'duplicate', 'duplicate-segment'),
        throwsA(anything),
      );
      expect(await db.database.query('events'), hasLength(1));
      await CompleteEvent(
        repository: events,
        now: () => now.add(const Duration(minutes: 1)),
      )(event.id);
      expect(
        (await repo.getPlanItems('plan')).first.status,
        PlanItemStatus.done,
      );
      await RestoreEvent(
        repository: events,
        now: () => now.add(const Duration(minutes: 2)),
      )(event.id);
      expect(
        (await repo.getPlanItems('plan')).first.status,
        PlanItemStatus.dispatched,
      );
    },
  );
  test(
    'late failure rolls back new execution and previous running pause',
    () async {
      await start('one', 'e', 's');
      await expectLater(start('two', 'e2', 's'), throwsA(anything));
      expect((await events.getEvent('e'))!.status, EventStatus.running);
      expect((await events.getRunSegments('e')).single.endedAt, isNull);
      expect(await events.getEvent('e2'), isNull);
      expect(
        (await repo.getPlanItems('plan')).last.status,
        PlanItemStatus.next,
      );
      expect(await events.getEventDayPlans('2026-09-14'), hasLength(1));
      await start('two', 'e2', 's2');
      expect((await events.getEvent('e'))!.status, EventStatus.paused);
      expect((await events.getRunSegments('e')).single.endedAt, now);
      expect((await events.getEvent('e2'))!.status, EventStatus.running);
    },
  );
  test(
    'starting PlanItem pauses Routine atomically, including failure rollback',
    () async {
      final routine = Routine(
        id: 'routine',
        name: 'Routine',
        recurrence: RoutineRecurrence.daily,
        weekdayMask: 0,
        isActive: true,
        sortOrder: 0,
        createdAt: now,
        updatedAt: now,
      );
      await events.insertRoutine(routine);
      var id = 0;
      await RoutineService(
        repository: events,
        newId: () => 'routine-${id++}',
        now: () => now,
      ).start(routine);
      final running = (await events.getRunningRoutineExecution())!;
      await db.database.execute(
        "CREATE TRIGGER fail_planned_start BEFORE INSERT ON event_day_plans BEGIN SELECT RAISE(ABORT, 'test'); END",
      );
      await expectLater(start('one', 'e', 's'), throwsA(anything));
      expect((await events.getRunningRoutineExecution())!.id, running.id);
      expect(
        (await events.getRoutineRunSegments(running.id)).single.endedAt,
        isNull,
      );
      await emptyExecution();
      await db.database.execute('DROP TRIGGER fail_planned_start');
      await start('one', 'e', 's');
      expect(await events.getRunningRoutineExecution(), isNull);
      expect(
        (await events.getRoutineRunSegments(running.id)).single.endedAt,
        now,
      );
      expect((await events.getEvent('e'))!.status, EventStatus.running);
    },
  );
  test(
    'concurrent starts cannot duplicate a PlanItem or leave two running',
    () async {
      final results = await Future.wait([
        start(
          'one',
          'e',
          's',
        ).then<Object?>((v) => v, onError: (Object e) => e),
        start(
          'one',
          'e2',
          's2',
        ).then<Object?>((v) => v, onError: (Object e) => e),
      ]);
      expect(results.whereType<Exception>(), hasLength(1));
      expect(await db.database.query('events'), hasLength(1));
      expect(await db.database.query('run_segments'), hasLength(1));
      await expectLater(
        repo.editPlanItem('one', title: 'Too late', now: now),
        throwsA(anything),
      );
      await expectLater(
        repo.setPlanItemStatus('one', PlanItemStatus.dropped, now),
        throwsA(anything),
      );
      await expectLater(repo.deletePlanItem('one'), throwsA(anything));
    },
  );
  test('legacy draft reads as next without changing stored facts', () async {
    await db.database.update(
      'plan_items',
      {'status': 'draft'},
      where: 'id = ?',
      whereArgs: ['one'],
    );
    final before = await db.database.query('plan_items');
    await planning.load();
    expect(planning.projectedTodayItems, hasLength(2));
    expect(planning.itemsFor('plan').first.status, PlanItemStatus.next);
    expect(await db.database.query('plan_items'), before);
    await start('one', 'e', 's');
    expect(
      (await repo.getPlanItems('plan')).first.status,
      PlanItemStatus.dispatched,
    );
  });
  test('Home recommendations do not ingest the projection', () async {
    for (var i = 0; i < 40; i++) {
      await repo.createPlanItem(
        id: 'many-$i',
        planId: 'plan',
        title: 'Item $i',
        now: now,
      );
    }
    await planning.load();
    await execution.load();
    expect(planning.projectedTodayItems, hasLength(42));
    expect(execution.homeRecommendations, isEmpty);
    await emptyExecution();
  });
  test('separate Windows and Android databases sync legacy values and running execution', () async {
    final android = await AppDatabase.open('${directory.path}/android.db');
    try {
      await db.database.update(
        'plan_items',
        {'status': 'draft'},
        where: 'id = ?',
        whereArgs: ['one'],
      );
      SyncSnapshot? baseline;
      Future<void> sync() async {
        final snapshot = await SqliteSyncSnapshotAdapter(db.database).read();
        const executor = SqliteSyncMutationExecutor();
        if (baseline == null) {
          await android.database.update('dataset_metadata', {
            'generation': snapshot.datasetGeneration,
          });
          await executor.applyDatabase(android, [
            for (final r in snapshot.records) SyncMutation.upsertRecord(r),
            for (final l in snapshot.lists) SyncMutation.applyList(l),
          ]);
        } else {
          final peer = await SqliteSyncSnapshotAdapter(android.database).read();
          final preview = const SyncCompareEngine().compare(
            windows: snapshot,
            android: peer,
            baseline: baseline!,
          );
          final resolved = ResolvedSyncPlan(preview: preview);
          expect(resolved.unresolvedKeys, isEmpty);
          final plan = const SyncPlanCompiler().compile(
            resolved: resolved,
            windows: snapshot,
            android: peer,
            baseline: baseline!,
          );
          await executor.applyDatabase(db, plan.windowsOperations);
          await executor.applyDatabase(android, plan.androidOperations);
        }
        baseline = await SqliteSyncSnapshotAdapter(db.database).read();
        expect(
          (await SqliteSyncSnapshotAdapter(
            android.database,
          ).read()).businessFingerprintSha256,
          baseline!.businessFingerprintSha256,
        );
        for (final database in [db, android]) {
          expect(
            await database.database.rawQuery('PRAGMA foreign_key_check'),
            isEmpty,
          );
        }
      }

      await sync();
      expect(
        (await SqlitePlanningRepository(android).getPlanItems('plan'))
            .first
            .status,
        PlanItemStatus.next,
      );
      await start('one', 'e', 's');
      await sync();
      expect(
        (await SqliteEventRepository(android).getEvent('e'))!.status,
        EventStatus.running,
      );
      expect(
        (await SqliteEventRepository(android).getRunSegments('e'))
            .single
            .endedAt,
        isNull,
      );
      expect(
        (await SqlitePlanningRepository(android).getPlanItems('plan'))
            .first
            .status,
        PlanItemStatus.dispatched,
      );
    } finally {
      await android.close();
    }
  });
}
