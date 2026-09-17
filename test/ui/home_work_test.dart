import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/app.dart';
import 'package:jax/core/entities/plan.dart';
import 'package:jax/core/entities/plan_item.dart';
import 'package:jax/core/entities/event_day_plan.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';
import 'package:jax/data/repositories/sqlite_planning_repository.dart';
import 'package:jax/data/repositories/sqlite_world_node_repository.dart';
import 'package:jax/ui/controllers/event_controller.dart';
import 'package:jax/ui/controllers/planning_controller.dart';
import 'package:jax/ui/pages/home_page.dart';
import 'package:jax/ui/pages/planning_page.dart';

import '../support/world_map_fixture.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets(
      'Category planning return, real dispatch takeover, paused/waiting resume and eligibility $platform',
      (tester) async {
        await tester.runAsync(() async {
          await tester.binding.setSurfaceSize(
            Size(platform == TargetPlatform.android ? 390 : 1200, 1000),
          );
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final db = await AppDatabase.inMemory();
          addTearDown(db.close);
          await seedWorldMapFixture(db);
          final repo = SqlitePlanningRepository(db),
              world = SqliteWorldNodeRepository(db);
          final events = _DelayedEvents(db);
          var seq = 0;
          var now = DateTime(2026, 9, 15, 10);
          final ec = EventController(
            repository: events,
            newId: () => 'e-${seq++}',
            now: () => now,
          );
          final pc = PlanningController(
            planningRepository: repo,
            worldNodeRepository: world,
            eventRepository: events,
            newId: () => 'p-${seq++}',
            now: () => now,
          );
          addTearDown(ec.dispose);
          addTearDown(pc.dispose);
          await world.setWorldNodeFocus(mapNodeId(0), true, now);
          await ec.load();
          await pc.load();
          Future<void> settle() async {
            await Future<void>.delayed(const Duration(milliseconds: 180));
            await tester.pumpAndSettle();
          }

          Future<String> facts() async {
            final result = <String, Object?>{};
            for (final row in await db.database.rawQuery(
              "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
            )) {
              final name = row['name'] as String;
              result[name] = await db.database.query(name);
            }
            return jsonEncode(result);
          }

          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(platform: platform),
              home: Scaffold(
                body: HomePage(
                  controller: ec,
                  planningController: pc,
                  now: () => now,
                  onOpenEvents: () {},
                ),
              ),
            ),
          );
          await settle();
          final before = await facts();
          await tester.tap(
            find.byKey(const ValueKey('home-category-entry-research')),
          );
          await settle();
          expect(find.text('下一步 0'), findsOneWidget);
          expect(find.text('下一步 1'), findsOneWidget);
          expect(find.text('snowman粒子'), findsOneWidget);
          expect(find.text('还没有可执行步骤'), findsOneWidget);
          expect(find.text('粗圆柱'), findsOneWidget);
          expect(
            tester.getTopLeft(find.text('粗圆柱')).dy,
            lessThan(tester.getTopLeft(find.text('下一步 0')).dy),
          );
          expect(find.text('科研'), findsOneWidget);
          expect(await facts(), before);
          await tester.tap(find.byKey(ValueKey('home-plan-${mapNodeId(3)}')));
          await settle();
          expect(find.byType(PlanDetailPage), findsOneWidget);
          expect(
            tester
                .widget<PlanDetailPage>(find.byType(PlanDetailPage))
                .worldNodeId,
            mapNodeId(3),
          );
          expect(await facts(), before);
          await tester.enterText(
            find.byKey(const ValueKey('plan-item-title')),
            '规划中新步骤',
          );
          await settle();
          await tester.tap(find.byKey(const ValueKey('add-plan-item')));
          await settle();
          if (platform == TargetPlatform.windows) {
            FocusManager.instance.primaryFocus?.unfocus();
            await settle();
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          } else {
            await tester.pageBack();
          }
          await settle();
          expect(
            find.byKey(const ValueKey('home-category-view')),
            findsOneWidget,
          );
          expect(find.text('规划中新步骤'), findsOneWidget);
          expect(find.byKey(const ValueKey('home-root-ask')), findsNothing);
          await tester.tap(
            find.byKey(const ValueKey('home-category-start-fixture-step-0')),
          );
          for (var frame = 0; frame < 20; frame++) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            await tester.pump();
            expect(find.text('下一步 0'), findsOneWidget);
          }
          await settle();
          expect(
            find.byKey(const ValueKey('home-running-hero')),
            findsOneWidget,
          );
          expect(
            (await repo.getPlanItems('fixture-plan')).first.status,
            PlanItemStatus.dispatched,
          );
          var event = ec.runningEvent!;
          expect(event.sourcePlanItemId, 'fixture-step-0');
          now = now.add(const Duration(minutes: 1));
          await ec.pause(event.id);
          await settle();
          expect(
            find.byKey(const ValueKey('home-category-view')),
            findsOneWidget,
          );
          expect(find.text('下一步 0'), findsOneWidget);
          expect(find.text('已暂停'), findsOneWidget);
          final row = find.byKey(
            const ValueKey('home-category-plan-fixture-step-0'),
          );
          expect(
            find.descendant(of: row, matching: find.text('继续')),
            findsOneWidget,
          );
          await tester.tap(
            find.byKey(const ValueKey('home-category-start-fixture-step-0')),
          );
          await settle();
          now = now.add(const Duration(minutes: 1));
          await ec.wait(event.id);
          await settle();
          expect(find.text('下一步 0'), findsOneWidget);
          expect(find.text('等待中'), findsOneWidget);
          await tester.tap(
            find.byKey(const ValueKey('home-category-start-fixture-step-0')),
          );
          await settle();
          expect(ec.runningEvent!.id, event.id);
          expect(await events.getAllRunSegments(), hasLength(3));
          now = now.add(const Duration(minutes: 1));
          await ec.wait(event.id);
          await settle();
          await tester.tap(
            find.byKey(const ValueKey('home-category-complete-fixture-step-0')),
          );
          await settle();
          expect(find.text('下一步 0'), findsNothing);
          await repo.setPlanItemStatus(
            'fixture-step-1',
            PlanItemStatus.dropped,
            now,
          );
          await pc.load();
          await settle();
          expect(find.text('下一步 1'), findsNothing);
          await world.setWorldNodeFocus(mapNodeId(3), false, now);
          await pc.load();
          await settle();
          expect(find.text('规划中新步骤'), findsNothing);
          await world.setWorldNodeFocus(mapNodeId(3), true, now);
          await repo.setPlanStatus('fixture-plan', PlanStatus.ended, now);
          await pc.load();
          await settle();
          expect(find.text('规划中新步骤'), findsNothing);
          expect(find.text('WCA粒子'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        });
      },
    );
  }
  testWidgets(
    'Category context survives actual app tab navigation and preserves scroll',
    (tester) async {
      await tester.runAsync(() async {
        await tester.binding.setSurfaceSize(const Size(1000, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final db = await AppDatabase.inMemory();
        addTearDown(db.close);
        await seedWorldMapFixture(db);
        final events = SqliteEventRepository(db),
            world = SqliteWorldNodeRepository(db),
            plans = SqlitePlanningRepository(db);
        final now = DateTime(2026, 9, 15, 10);
        for (var i = 2; i < 24; i++) {
          await plans.createPlanItem(
            id: 'scroll-$i',
            planId: 'fixture-plan',
            title: '滚动步骤 $i',
            now: now,
          );
        }
        await tester.pumpWidget(
          JaxApp(
            repository: events,
            planningRepository: plans,
            worldNodeRepository: world,
            now: () => now,
          ),
        );
        final home = tester.widget<HomePage>(find.byType(HomePage));
        Future<void> settle() async {
          // Keep controller references when navigation removes the Home widget.
          // Native database work is not represented by scheduled UI frames.
          for (var attempt = 0; attempt < 200; attempt++) {
            await tester.pumpAndSettle();
            if (!home.controller.loading &&
                home.planningController?.loading != true) {
              return;
            }
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
          fail('Database-backed controllers did not finish loading.');
        }

        await settle();
        await tester.tap(
          find.byKey(const ValueKey('home-category-entry-research')),
        );
        await settle();
        await tester.drag(
          find.byKey(const PageStorageKey('home-category-scroll-research')),
          const Offset(0, -500),
        );
        await settle();
        final scroll = find
            .descendant(
              of: find.byKey(
                const PageStorageKey('home-category-scroll-research'),
              ),
              matching: find.byType(Scrollable),
            )
            .first;
        final offset = tester.state<ScrollableState>(scroll).position.pixels;
        expect(offset, greaterThan(100));
        await tester.tap(find.text('今日').last);
        await settle();
        await tester.tap(find.text('首页').last);
        await settle();
        expect(
          find.byKey(const ValueKey('home-category-view')),
          findsOneWidget,
        );
        final backOffset = tester
            .state<ScrollableState>(
              find
                  .descendant(
                    of: find.byKey(
                      const PageStorageKey('home-category-scroll-research'),
                    ),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            )
            .position
            .pixels;
        expect(backOffset, closeTo(offset, 1));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    },
  );
}

class _DelayedEvents extends SqliteEventRepository {
  _DelayedEvents(super.db);
  @override
  Future<List<EventDayPlan>> getEventDayPlans(String dayKey) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    return super.getEventDayPlans(dayKey);
  }
}
