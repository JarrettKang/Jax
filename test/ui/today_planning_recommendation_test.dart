import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/plan_item.dart';
import 'package:jax/core/entities/event_day_plan.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';
import 'package:jax/data/repositories/sqlite_planning_repository.dart';
import 'package:jax/data/repositories/sqlite_world_node_repository.dart';
import 'package:jax/ui/controllers/event_controller.dart';
import 'package:jax/ui/controllers/planning_controller.dart';
import 'package:jax/ui/pages/events_page.dart';

import '../support/world_map_fixture.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets('Today projects original steps and starts in place $platform', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await tester.binding.setSurfaceSize(
          Size(platform == TargetPlatform.android ? 390 : 1200, 900),
        );
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final db = await AppDatabase.inMemory();
        addTearDown(db.close);
        await seedWorldMapFixture(db);
        final repo = SqlitePlanningRepository(db);
        final events = _DelayedDayPlanRepository(db);
        var id = 0;
        final ec = EventController(
          repository: events,
          newId: () => 'event-${id++}',
          now: DateTime.now,
        );
        final pc = PlanningController(
          planningRepository: repo,
          worldNodeRepository: SqliteWorldNodeRepository(db),
          eventRepository: events,
          newId: () => 'planned-${id++}',
          now: DateTime.now,
        );
        addTearDown(ec.dispose);
        addTearDown(pc.dispose);
        await ec.load();
        await pc.load();
        Future<void> settle() async {
          await Future<void>.delayed(const Duration(milliseconds: 150));
          await tester.pumpAndSettle();
        }

        Widget page() => MaterialApp(
          theme: ThemeData(platform: platform),
          home: Scaffold(
            body: EventsPage(controller: ec, planningController: pc),
          ),
        );
        await tester.pumpWidget(page());
        await settle();
        expect(find.text('下一步 0'), findsOneWidget);
        expect(find.text('下一步 1'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('today-recommendations')),
          findsNothing,
        );
        expect(find.text('加入今日'), findsNothing);
        expect(find.byTooltip('移出今日'), findsNothing);
        expect(find.text('今天先不处理'), findsNothing);
        expect(find.byTooltip('更多操作'), findsNothing);
        for (final table in ['events', 'event_day_plans', 'run_segments']) {
          expect(await db.database.query(table), isEmpty);
        }
        await pc.editItem(pc.itemsFor('fixture-plan').first, 'New title', null);
        await settle();
        expect(find.text('New title'), findsOneWidget);
        await db.database.update(
          'world_nodes',
          {'is_focused': 0},
          where: 'id = ?',
          whereArgs: [mapNodeId(3)],
        );
        await pc.load();
        await settle();
        expect(find.text('New title'), findsNothing);
        await db.database.update(
          'world_nodes',
          {'is_focused': 1},
          where: 'id = ?',
          whereArgs: [mapNodeId(3)],
        );
        await pc.load();
        await settle();
        expect(find.text('New title'), findsOneWidget);
        // Start the second row: its logical key and position must not move ahead of the first.
        final before = tester.getTopLeft(find.text('下一步 1')).dy;
        events.delayDayPlans = true;
        await tester.tap(
          find.byKey(const ValueKey('today-plan-start-fixture-step-1')),
        );
        for (var frame = 0; frame < 20; frame++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pumpWidget(page());
          expect(find.text('下一步 1'), findsOneWidget, reason: 'frame $frame');
        }
        await settle();
        expect(tester.getTopLeft(find.text('下一步 1')).dy, lessThan(before));
        expect(find.text('正在进行'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('today-plan-start-fixture-step-1')),
          findsNothing,
        );
        expect(
          pc.itemsFor('fixture-plan').last.status,
          PlanItemStatus.dispatched,
        );
        expect(ec.todayEvents.single.status, EventStatus.running);
        expect(
          (await events.getRunSegments(ec.todayEvents.single.id))
              .single
              .endedAt,
          isNull,
        );
        expect(find.text('New title'), findsOneWidget);
        await pc.setItemStatus(
          pc.itemsFor('fixture-plan').first,
          PlanItemStatus.dropped,
        );
        await settle();
        expect(find.text('New title'), findsNothing);
        await db.database.update(
          'world_nodes',
          {'is_focused': 0},
          where: 'id = ?',
          whereArgs: [mapNodeId(3)],
        );
        await pc.load();
        await settle();
        expect(find.text('下一步 1'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    });
  }
}

// Expose the Event-loaded / day-plan-not-yet-loaded interval deterministically.
class _DelayedDayPlanRepository extends SqliteEventRepository {
  _DelayedDayPlanRepository(super.appDatabase);
  bool delayDayPlans = false;
  @override
  Future<List<EventDayPlan>> getEventDayPlans(String dayKey) async {
    if (delayDayPlans) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    return super.getEventDayPlans(dayKey);
  }
}
