import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/plan.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';
import 'package:jax/data/repositories/sqlite_planning_repository.dart';
import 'package:jax/data/repositories/sqlite_world_node_repository.dart';
import 'package:jax/ui/controllers/event_controller.dart';
import 'package:jax/ui/controllers/planning_controller.dart';
import 'package:jax/ui/controllers/home_view_state.dart';

import '../support/world_map_fixture.dart';

void main() {
  test('Work includes legacy unfinished linked Event outside Today, excludes promoted steps and retains ended-plan executions', () async {
    final db = await AppDatabase.inMemory();
    addTearDown(db.close);
    await seedWorldMapFixture(db);
    final plans = SqlitePlanningRepository(db),
        world = SqliteWorldNodeRepository(db),
        events = SqliteEventRepository(db);
    var now = DateTime(2026, 9, 15, 10);
    var id = 0;
    final ec = EventController(
      repository: events,
      newId: () => 'id-${id++}',
      now: () => now,
    );
    final pc = PlanningController(
      planningRepository: plans,
      worldNodeRepository: world,
      eventRepository: events,
      newId: () =>
          '40000000-0000-4000-8000-${(100 + id++).toString().padLeft(12, '0')}',
      now: () => now,
    );
    addTearDown(ec.dispose);
    addTearDown(pc.dispose);
    await plans.dispatchPlanItems(
      eventIdsByPlanItemId: {'fixture-step-0': 'legacy'},
      dayKey: '2026-09-10',
      now: now,
    );
    await ec.load();
    await pc.load();
    expect(ec.todayEvents, isEmpty);
    var group = homeCategoryGroups(pc, ec, categoryId: 'research').single;
    expect(group.items, hasLength(2));
    expect(group.items.first.event!.id, 'legacy');
    expect(group.items.first.event!.status, EventStatus.pending);
    expect(group.items.first.identity, 'plan-fixture-step-0');
    await pc.promoteItem(pc.itemsFor('fixture-plan').last);
    group = homeCategoryGroups(
      pc,
      ec,
      categoryId: 'research',
    ).firstWhere((g) => g.node.id == mapNodeId(3));
    expect(group.items, hasLength(1));
    await plans.setPlanStatus('fixture-plan', PlanStatus.ended, now);
    await pc.load();
    group = homeCategoryGroups(
      pc,
      ec,
      categoryId: 'research',
    ).firstWhere((g) => g.node.id == mapNodeId(3));
    expect(group.items.single.event!.id, 'legacy');
    expect((await events.getEvent('legacy'))!.status, EventStatus.pending);
    expect(await ec.start('legacy'), isNull);
    now = now.add(const Duration(minutes: 1));
    expect(await ec.pause('legacy'), isNull);
    expect(
      homeCategoryGroups(
        pc,
        ec,
        categoryId: 'research',
      ).firstWhere((g) => g.node.id == mapNodeId(3)).items.single.event!.status,
      EventStatus.paused,
    );
    expect(await ec.resume('legacy'), isNull);
    now = now.add(const Duration(minutes: 1));
    expect(await ec.wait('legacy'), isNull);
    expect(
      homeCategoryGroups(
        pc,
        ec,
        categoryId: 'research',
      ).firstWhere((g) => g.node.id == mapNodeId(3)).items.single.event!.status,
      EventStatus.waiting,
    );
    final segments = await events.getAllRunSegments();
    expect(await ec.complete('legacy'), isNull);
    expect(
      homeCategoryGroups(
        pc,
        ec,
        categoryId: 'research',
      ).firstWhere((g) => g.node.id == mapNodeId(3)).items,
      isEmpty,
    );
    expect(
      (await events.getAllRunSegments()).map(
        (s) => (s.id, s.startedAt, s.endedAt),
      ),
      segments.map((s) => (s.id, s.startedAt, s.endedAt)),
    );

    await world.setWorldNodeFocus(mapNodeId(3), false, now);
    await pc.load();
    expect(
      homeCategoryGroups(
        pc,
        ec,
        categoryId: 'research',
      ).where((g) => g.node.id == mapNodeId(3)),
      isEmpty,
    );
  });
}
