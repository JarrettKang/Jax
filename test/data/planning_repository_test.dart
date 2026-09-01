import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/plan.dart';
import 'package:jax/core/entities/plan_item.dart';
import 'package:jax/core/entities/world_node.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/repositories/sqlite_planning_repository.dart';
import 'package:jax/data/repositories/sqlite_world_node_repository.dart';

void main() {
  late AppDatabase app;
  late SqlitePlanningRepository plans;
  late SqliteWorldNodeRepository nodes;

  setUp(() async {
    app = await AppDatabase.inMemory();
    plans = SqlitePlanningRepository(app);
    nodes = SqliteWorldNodeRepository(app);
  });
  tearDown(() => app.close());

  test('Plan lifecycle and per-WorldNode current invariant', () async {
    final a = _node('11111111-1111-4111-8111-111111111111', 'A');
    final b = _node('22222222-2222-4222-8222-222222222222', 'B');
    await nodes.insertWorldNode(a);
    await nodes.insertWorldNode(b);

    final first = await plans.createPlan(
      id: 'plan-a-1',
      worldNodeId: a.id,
      now: _time(10),
    );
    expect(first.status, PlanStatus.focused);
    expect(first.roundNumber, 1);

    await expectLater(
      plans.createPlan(id: 'duplicate', worldNodeId: a.id, now: _time(11)),
      throwsA(anything),
    );
    await plans.setPlanStatus(first.id, PlanStatus.waiting, _time(20));
    await expectLater(
      plans.createPlan(
        id: 'still-duplicate',
        worldNodeId: a.id,
        now: _time(21),
      ),
      throwsA(anything),
    );
    await plans.setPlanStatus(first.id, PlanStatus.focused, _time(30));

    final parallel = await plans.createPlan(
      id: 'plan-b-1',
      worldNodeId: b.id,
      now: _time(40),
    );
    expect(parallel.status, PlanStatus.focused);

    await plans.setPlanStatus(first.id, PlanStatus.ended, _time(50));
    final ended = await plans.getPlan(first.id);
    expect(ended!.status, PlanStatus.ended);
    expect(ended.endedAt, _time(50));
    await expectLater(
      plans.setPlanStatus(first.id, PlanStatus.focused, _time(51)),
      throwsA(anything),
    );

    final second = await plans.createPlan(
      id: 'plan-a-2',
      worldNodeId: a.id,
      now: _time(60),
    );
    expect(second.roundNumber, 2);
  });

  test('PlanItem lifecycle, delete, and scoped reorder', () async {
    final a = _node('11111111-1111-4111-8111-111111111111', 'A');
    final b = _node('22222222-2222-4222-8222-222222222222', 'B');
    await nodes.insertWorldNode(a);
    await nodes.insertWorldNode(b);
    final planA = await plans.createPlan(
      id: 'plan-a',
      worldNodeId: a.id,
      now: _time(1),
    );
    final planB = await plans.createPlan(
      id: 'plan-b',
      worldNodeId: b.id,
      now: _time(1),
    );
    for (final value in [('a', 'A'), ('b', 'B'), ('c', 'C')]) {
      await plans.createPlanItem(
        id: value.$1,
        planId: planA.id,
        title: value.$2,
        now: _time(10),
      );
    }
    await plans.createPlanItem(
      id: 'other',
      planId: planB.id,
      title: 'Other',
      now: _time(10),
    );

    await plans.setPlanItemStatus('a', PlanItemStatus.next, _time(20));
    await plans.setPlanItemStatus('a', PlanItemStatus.draft, _time(21));
    await plans.setPlanItemStatus('a', PlanItemStatus.dropped, _time(22));
    await plans.setPlanItemStatus('a', PlanItemStatus.draft, _time(23));
    await expectLater(
      plans.setPlanItemStatus('a', PlanItemStatus.dispatched, _time(24)),
      throwsA(anything),
    );
    await expectLater(
      plans.setPlanItemStatus('a', PlanItemStatus.done, _time(24)),
      throwsA(anything),
    );

    await plans.reorderPlanItem('b', 0, _time(30));
    expect((await plans.getPlanItems(planA.id)).map((i) => i.id), [
      'b',
      'a',
      'c',
    ]);
    expect((await plans.getPlanItems(planB.id)).single.id, 'other');

    await plans.setPlanItemStatus('a', PlanItemStatus.dropped, _time(31));
    await expectLater(plans.deletePlanItem('a'), throwsA(anything));
    await plans.deletePlanItem('c');
    expect((await plans.getPlanItems(planA.id)).map((i) => i.id), ['b', 'a']);
  });

  test(
    'ending Plan preserves item states and never completes WorldNode',
    () async {
      final node = _node('11111111-1111-4111-8111-111111111111', 'A');
      await nodes.insertWorldNode(node);
      final plan = await plans.createPlan(
        id: 'plan',
        worldNodeId: node.id,
        now: _time(1),
      );
      await plans.createPlanItem(
        id: 'next',
        planId: plan.id,
        title: 'Next',
        now: _time(2),
      );
      await plans.createPlanItem(
        id: 'draft',
        planId: plan.id,
        title: 'Draft',
        now: _time(2),
      );
      await plans.createPlanItem(
        id: 'drop',
        planId: plan.id,
        title: 'Drop',
        now: _time(2),
      );
      await plans.setPlanItemStatus('next', PlanItemStatus.next, _time(3));
      await plans.setPlanItemStatus('drop', PlanItemStatus.dropped, _time(3));

      await expectLater(
        nodes.updateWorldNode(node.copyWith(status: WorldNodeStatus.completed)),
        throwsStateError,
      );
      await plans.setPlanStatus(plan.id, PlanStatus.ended, _time(4));
      expect((await plans.getPlanItems(plan.id)).map((i) => i.status), [
        PlanItemStatus.next,
        PlanItemStatus.draft,
        PlanItemStatus.dropped,
      ]);
      expect(
        (await nodes.getWorldNode(node.id))!.status,
        WorldNodeStatus.inProgress,
      );
      await nodes.updateWorldNode(
        node.copyWith(status: WorldNodeStatus.completed),
      );
      expect(
        (await nodes.getWorldNode(node.id))!.status,
        WorldNodeStatus.completed,
      );
    },
  );

  test('Planning operations do not change execution tables', () async {
    final node = _node('11111111-1111-4111-8111-111111111111', 'A');
    await nodes.insertWorldNode(node);
    Future<List<int>> counts() async => Future.wait([
      for (final table in [
        'events',
        'event_day_plans',
        'run_segments',
        'routine_executions',
      ])
        app.database
            .rawQuery('SELECT count(*) count FROM $table')
            .then((r) => (r.single['count'] as num).toInt()),
    ]);
    final before = await counts();
    final plan = await plans.createPlan(
      id: 'plan',
      worldNodeId: node.id,
      now: _time(1),
    );
    final item = await plans.createPlanItem(
      id: 'item',
      planId: plan.id,
      title: 'Step',
      now: _time(2),
    );
    await plans.setPlanItemStatus(item.id, PlanItemStatus.next, _time(3));
    await plans.setPlanStatus(plan.id, PlanStatus.ended, _time(4));
    expect(await counts(), before);
  });

  test('whole Plan delete is enforced by execution history and source links', () async {
    final node = _node('11111111-1111-4111-8111-111111111111', 'A');
    await nodes.insertWorldNode(node);
    final deletable = await plans.createPlan(
      id: 'deletable',
      worldNodeId: node.id,
      now: _time(1),
    );
    await plans.createPlanItem(
      id: 'draft',
      planId: deletable.id,
      title: 'Draft',
      now: _time(2),
    );
    await plans.deletePlan(deletable.id);
    expect(await plans.getPlan(deletable.id), isNull);
    expect(await plans.getPlanItems(deletable.id), isEmpty);
    expect(await nodes.getWorldNode(node.id), isNotNull);
    expect(
      (await app.database.query('sync_tombstones')).map(
        (row) => '${row['entity_type']}:${row['entity_id']}',
      ),
      containsAll(['plan:deletable', 'planItem:draft']),
    );

    final linked = await plans.createPlan(
      id: 'linked',
      worldNodeId: node.id,
      now: _time(3),
    );
    await plans.createPlanItem(
      id: 'linked-item',
      planId: linked.id,
      title: 'Linked',
      now: _time(4),
    );
    await app.database.insert('events', {
      'id': 'event',
      'name': 'Event',
      'status': 'pending',
      'source_plan_item_id': 'linked-item',
      'category_id': null,
      'created_at_utc': 4,
      'updated_at_utc': 4,
    });
    await expectLater(plans.deletePlan(linked.id), throwsA(anything));
    await app.database.delete('events', where: 'id = ?', whereArgs: ['event']);
    await app.database.update(
      'plan_items',
      {'status': 'dispatched'},
      where: 'id = ?',
      whereArgs: ['linked-item'],
    );
    await expectLater(plans.deletePlan(linked.id), throwsA(anything));
  });
}

WorldNode _node(String id, String name) => WorldNode(
  id: id,
  name: name,
  status: WorldNodeStatus.inProgress,
  sortOrder: 0,
  createdAt: _time(0),
  updatedAt: _time(0),
);

DateTime _time(int value) =>
    DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
