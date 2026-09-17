import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/category.dart';
import 'package:jax/core/entities/plan.dart';
import 'package:jax/core/entities/plan_item.dart';
import 'package:jax/core/entities/world_node.dart';
import 'package:jax/core/use_cases/complete_event.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';
import 'package:jax/data/repositories/sqlite_planning_repository.dart';
import 'package:jax/data/repositories/sqlite_world_node_repository.dart';
import 'package:jax/data/sync/sqlite_sync_readiness.dart';
import 'package:jax/ui/controllers/planning_controller.dart';

String nodeId(int id) =>
    '00000000-0000-4000-8000-${id.toString().padLeft(12, '0')}';

void main() {
  late Directory dir;
  late AppDatabase db;
  late SqlitePlanningRepository plans;
  late SqliteWorldNodeRepository worlds;
  late SqliteEventRepository events;
  late PlanningController controller;
  final now = DateTime.utc(2026, 9, 14, 6);
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('jax-promote-');
    db = await AppDatabase.open('${dir.path}/db.sqlite');
    plans = SqlitePlanningRepository(db);
    worlds = SqliteWorldNodeRepository(db);
    events = SqliteEventRepository(db);
    await events.insertCategory(
      Category(
        id: 'research',
        name: 'Research',
        sortOrder: 0,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await worlds.insertWorldNode(
      WorldNode(
        id: nodeId(1),
        name: 'Parent',
        status: WorldNodeStatus.inProgress,
        isFocused: true,
        categoryId: 'research',
        sortOrder: 0,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await worlds.insertWorldNode(
      WorldNode(
        id: nodeId(2),
        name: 'Sibling',
        status: WorldNodeStatus.inProgress,
        isFocused: false,
        parentWorldNodeId: nodeId(1),
        sortOrder: 0,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await plans.createPlan(id: 'plan', worldNodeId: nodeId(1), now: now);
    for (final id in ['before', 'target', 'after']) {
      await plans.createPlanItem(
        id: id,
        planId: 'plan',
        title: id,
        note: 'Note $id',
        now: now,
      );
    }
    var seq = 10;
    controller = PlanningController(
      planningRepository: plans,
      worldNodeRepository: worlds,
      eventRepository: events,
      newId: () => nodeId(seq++),
      now: () => now.add(const Duration(seconds: 1)),
    );
    await controller.load();
  });
  tearDown(() async {
    controller.dispose();
    await db.close();
    await dir.delete(recursive: true);
  });
  Future<WorldNode> promote() => plans.promotePlanItem(
    planItemId: 'target',
    worldNodeId: nodeId(3),
    now: now.add(const Duration(seconds: 1)),
  );
  Future<Map<String, Object?>> facts() async {
    final result = <String, Object?>{};
    for (final table in [
      'world_nodes',
      'plans',
      'plan_items',
      'events',
      'event_day_plans',
      'run_segments',
      'sync_tombstones',
    ]) {
      result[table] = await db.database.query(table, orderBy: 'rowid');
    }
    return result;
  }

  test('promotion preserves original facts, appends child, and creates no execution or Plan', () async {
    final before = await db.database.query('plan_items', orderBy: 'sort_order');
    final child = await promote();
    expect(child.name, 'target');
    expect(child.parentWorldNodeId, nodeId(1));
    expect(child.status, WorldNodeStatus.inProgress);
    expect(child.isFocused, isTrue);
    expect(child.categoryId, isNull);
    expect(child.sortOrder, 1);
    final after = await db.database.query('plan_items', orderBy: 'sort_order');
    expect(after.length, before.length);
    for (var i = 0; i < before.length; i++) {
      for (final key in before[i].keys.where(
        (k) => k != 'updated_at_utc' && k != 'promoted_world_node_id',
      )) {
        expect(after[i][key], before[i][key], reason: '$i $key');
      }
    }
    final reference = (await plans.getPlanItems('plan'))[1];
    expect(reference.type, PlanItemType.worldNodeReference);
    expect(reference.promotedWorldNodeId, child.id);
    expect(reference.isExecutable, isFalse);
    expect(await plans.getPlans(), hasLength(1));
    for (final table in [
      'events',
      'event_day_plans',
      'run_segments',
      'sync_tombstones',
    ]) {
      expect(await db.database.query(table), isEmpty, reason: table);
    }
    await controller.load();
    expect(controller.categoryForNode(child)!.id, 'research');
    expect(controller.projectedTodayItems.map((i) => i.id), [
      'before',
      'after',
    ]);
    expect(await SqliteSyncReadiness(db).validate(), isEmpty);
  });
  test(
    'focus inheritance happens only once and child lazily gains its first Plan',
    () async {
      final child = await promote();
      await worlds.setWorldNodeFocus(
        nodeId(1),
        false,
        now.add(const Duration(seconds: 2)),
      );
      await controller.load();
      expect(controller.nodeFor(child.id)!.isFocused, isTrue);
      expect(controller.currentPlanFor(child.id), isNull);
      await controller.createFirstStep(
        child,
        'Child step',
        null,
        PlanItemStatus.next,
      );
      expect(controller.projectedTodayItems.map((i) => i.title), [
        'Child step',
      ]);
      expect(await plans.getPlans(), hasLength(2));
    },
  );
  test('unfocused parent is allowed and yields unfocused child', () async {
    await worlds.setWorldNodeFocus(nodeId(1), false, now);
    final child = await promote();
    expect(child.isFocused, isFalse);
    await controller.load();
    expect(controller.projectedTodayItems, isEmpty);
  });
  test('legacy draft is eligible without losing note or identity', () async {
    await db.database.update(
      'plan_items',
      {'status': 'draft'},
      where: 'id = ?',
      whereArgs: ['target'],
    );
    await promote();
    final item = (await plans.getPlanItems('plan'))[1];
    expect(item.isPromoted, isTrue);
    expect(item.note, 'Note target');
    expect(item.id, 'target');
  });
  test('reference is terminal across every ordinary step mutation', () async {
    await promote();
    final before = await facts();
    final actions = <Future<void> Function()>[
      () async {
        await promote();
      },
      () => plans.editPlanItem('target', title: 'Changed', now: now),
      () => plans.setPlanItemStatus('target', PlanItemStatus.next, now),
      () => plans.setPlanItemStatus('target', PlanItemStatus.dropped, now),
      () => plans.deletePlanItem('target'),
      () => plans.reorderPlanItem('target', 0, now),
      () async {
        await plans.startPlanItem(
          planItemId: 'target',
          eventId: 'e',
          segmentId: 's',
          dayKey: '2026-09-14',
          now: now,
        );
      },
      () async {
        await plans.dispatchPlanItems(
          eventIdsByPlanItemId: {'target': 'e'},
          dayKey: '2026-09-14',
          now: now,
        );
      },
    ];
    for (final action in actions) {
      await expectLater(action(), throwsA(anything));
      expect(await facts(), before);
    }
  });
  for (final status in ['dispatched', 'done', 'dropped', 'ended']) {
    test(
      '$status cannot promote and keeps execution facts untouched',
      () async {
        if (status == 'dropped') {
          await plans.setPlanItemStatus('target', PlanItemStatus.dropped, now);
        } else if (status == 'ended') {
          await plans.setPlanStatus('plan', PlanStatus.ended, now);
        } else {
          final e = await plans.startPlanItem(
            planItemId: 'target',
            eventId: 'e',
            segmentId: 's',
            dayKey: '2026-09-14',
            now: now,
          );
          if (status == 'done') {
            await CompleteEvent(
              repository: events,
              now: () => now.add(const Duration(minutes: 1)),
            )(e.id);
          }
        }
        final before = await facts();
        await expectLater(promote(), throwsA(anything));
        expect(await facts(), before);
      },
    );
  }
  test('any linked Event blocks promotion even with stale next status', () async {
    await plans.dispatchPlanItems(
      eventIdsByPlanItemId: {'target': 'e'},
      dayKey: '2026-09-14',
      now: now,
    );
    // Deliberately corrupt the status to exercise the independent Event check.
    await db.database.update(
      'plan_items',
      {'status': 'next'},
      where: 'id = ?',
      whereArgs: ['target'],
    );
    final before = await facts();
    await expectLater(promote(), throwsA(anything));
    expect(await facts(), before);
  });
  test(
    'late transaction failure rolls back child and original reference',
    () async {
      await db.database.execute(
        "CREATE TRIGGER fail_promotion BEFORE UPDATE OF promoted_world_node_id ON plan_items BEGIN SELECT RAISE(ABORT,'injected'); END",
      );
      final before = await facts();
      await expectLater(promote(), throwsA(anything));
      expect(await facts(), before);
    },
  );
  test('concurrent promotion creates exactly one child', () async {
    final results = await Future.wait([
      promote().then<Object?>((v) => v, onError: (Object e) => e),
      plans
          .promotePlanItem(
            planItemId: 'target',
            worldNodeId: nodeId(4),
            now: now,
          )
          .then<Object?>((v) => v, onError: (Object e) => e),
    ]);
    expect(results.whereType<WorldNode>(), hasLength(1));
    expect(await worlds.getWorldNodes(), hasLength(3));
  });
  test('rename, completed child, moved child and ended parent preserve reference semantics', () async {
    final child = await promote();
    await controller.load();
    await controller.renameWorldNode(child, 'Renamed child');
    expect(
      controller.promotedNodeFor(controller.itemsFor('plan')[1])!.name,
      'Renamed child',
    );
    await worlds.reparentWorldNode(
      child.id,
      null,
      'research',
      1,
      now.add(const Duration(seconds: 3)),
    );
    await worlds.updateWorldNode(
      (await worlds.getWorldNode(child.id))!
          .copyWith(status: WorldNodeStatus.completed),
    );
    await plans.setPlanStatus('plan', PlanStatus.ended, now);
    await controller.load();
    final ref = controller.itemsFor('plan')[1];
    expect(ref.isPromoted, isTrue);
    expect(controller.promotedNodeFor(ref)!.status, WorldNodeStatus.completed);
    expect(controller.promotedNodeFor(ref)!.parentWorldNodeId, isNull);
  });
  test('linked node deletion is restricted; deleting parent Plan leaves child independent', () async {
    final child = await promote();
    final before = await facts();
    await expectLater(
      db.database.delete('world_nodes', where: 'id = ?', whereArgs: [child.id]),
      throwsA(anything),
    );
    expect(await facts(), before);
    await plans.deletePlan('plan');
    expect(await worlds.getWorldNode(child.id), isNotNull);
    expect(
      await db.database.query(
        'sync_tombstones',
        where: "entity_type = 'planItem'",
      ),
      hasLength(3),
    );
    await db.database.delete(
      'world_nodes',
      where: 'id = ?',
      whereArgs: [child.id],
    );
    expect(await db.database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });
  test('v21 additive migration preserves all rows and tombstones; repeat open is idempotent', () async {
    await db.database.update(
      'plan_items',
      {'status': 'draft'},
      where: 'id = ?',
      whereArgs: ['target'],
    );
    await db.database.execute('DROP INDEX plan_items_promoted_world_node');
    await db.database.execute(
      'ALTER TABLE plan_items DROP COLUMN promoted_world_node_id',
    );
    await db.database.execute('PRAGMA user_version = 21');
    final old = await facts();
    await db.close();
    db = await AppDatabase.open('${dir.path}/db.sqlite');
    final migrated = await facts();
    final migratedItems = (migrated['plan_items']! as List)
        .map(
          (r) =>
              Map<String, Object?>.from(r as Map)
                ..remove('promoted_world_node_id'),
        )
        .toList();
    expect(migratedItems, old['plan_items']);
    for (final table in old.keys.where((k) => k != 'plan_items')) {
      expect(migrated[table], old[table], reason: table);
    }
    expect(
      (await db.database.rawQuery('PRAGMA user_version')).single.values.single,
      AppDatabase.schemaVersion,
    );
    expect(await SqliteSyncReadiness(db).validate(), isEmpty);
    await db.close();
    db = await AppDatabase.open('${dir.path}/db.sqlite');
    expect(await facts(), migrated);
  });
}
