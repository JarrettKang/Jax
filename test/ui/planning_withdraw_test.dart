import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/plan_item.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';
import 'package:jax/data/repositories/sqlite_planning_repository.dart';
import 'package:jax/data/repositories/sqlite_world_node_repository.dart';
import 'package:jax/ui/controllers/event_controller.dart';
import 'package:jax/ui/controllers/planning_controller.dart';
import 'package:jax/ui/pages/events_page.dart';
import 'package:jax/ui/pages/planning_page.dart';

import '../support/world_map_fixture.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets(
      'legacy pending Event withdrawal menus restore next $platform',
      (tester) async {
        await tester.runAsync(() async {
          Future<void> settle() async {
            await Future<void>.delayed(const Duration(milliseconds: 120));
            await tester.pumpAndSettle();
          }

          await tester.binding.setSurfaceSize(
            Size(platform == TargetPlatform.android ? 390 : 1200, 900),
          );
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final db = await AppDatabase.inMemory();
          addTearDown(db.close);
          await seedWorldMapFixture(db);
          final repo = SqlitePlanningRepository(db);
          final events = SqliteEventRepository(db);
          var id = 0;
          final now = DateTime.now;
          final ec = EventController(
            repository: events,
            newId: () => 'event-${id++}',
            now: now,
          );
          final pc = PlanningController(
            planningRepository: repo,
            worldNodeRepository: SqliteWorldNodeRepository(db),
            eventRepository: events,
            newId: () => 'event-${id++}',
            now: now,
            onExecutionChanged: ec.load,
          );
          addTearDown(ec.dispose);
          addTearDown(pc.dispose);
          await repo.setPlanItemStatus(
            'fixture-step-0',
            PlanItemStatus.next,
            now(),
          );
          await pc.load();
          await ec.load();
          // Only seed legacy pending Events here; no product UI can dispatch early.
          Future<void> seedLegacyEvent() async {
            await repo.dispatchPlanItems(
              eventIdsByPlanItemId: {'fixture-step-0': 'legacy-${id++}'},
              dayKey: ec.currentJaxDay.key,
              now: now(),
            );
            await pc.load();
            await ec.load();
          }

          Future<void> workspace() async {
            await tester.pumpWidget(
              MaterialApp(
                theme: ThemeData(platform: platform),
                home: PlanDetailPage(controller: pc, planId: 'fixture-plan'),
              ),
            );
            await settle();
          }

          Future<void> more(String key, String label) async {
            final menu = find.byKey(ValueKey(key));
            await tester.ensureVisible(menu);
            await tester.tap(menu);
            await settle();
            expect(find.text(label), findsOneWidget);
            await tester.tap(find.text(label));
            await settle();
          }

          await workspace();
          expect(pc.recommendationGroups.single.items.map((i) => i.id), [
            'fixture-step-0',
            'fixture-step-1',
          ]);
          await seedLegacyEvent();
          await settle();
          expect(
            pc.itemsFor('fixture-plan').first.status,
            PlanItemStatus.dispatched,
          );
          expect(ec.todayEvents, hasLength(1));
          await more('plan-item-more-fixture-step-0', '收回到计划');
          expect(pc.itemsFor('fixture-plan').first.status, PlanItemStatus.next);
          expect(ec.todayEvents, isEmpty);
          final title = find.byKey(const ValueKey('draft-edit-fixture-step-0'));
          await tester.ensureVisible(title);
          await tester.tap(title);
          await settle();
          await tester.enterText(
            find.byKey(const ValueKey('draft-title-fixture-step-0')),
            '测试2e5',
          );
          await tester.tap(
            find.byKey(const ValueKey('save-draft-fixture-step-0')),
          );
          await settle();
          await seedLegacyEvent();
          await settle();
          final event = ec.todayEvents.single;
          expect(event.name, '测试2e5');
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(platform: platform),
              home: Scaffold(
                body: EventsPage(controller: ec, planningController: pc),
              ),
            ),
          );
          await settle();
          // Planned Events retain withdrawal, but cannot be hidden from Today.
          expect(
            find.byKey(ValueKey('today-remove-${event.id}')),
            findsNothing,
          );
          expect(await ec.removeFromToday(event.id), isNotNull);
          await settle();
          expect(await events.getEvent(event.id), isNotNull);
          expect(
            pc.itemsFor('fixture-plan').first.status,
            PlanItemStatus.dispatched,
          );
          await ec.addToToday(event.id);
          await settle();
          await more('today-event-more-${event.id}', '收回到计划');
          expect(await events.getEvent(event.id), isNull);
          expect(ec.todayEvents, isEmpty);
          await seedLegacyEvent();
          await settle();
          final runningId = ec.todayEvents.single.id;
          expect(
            find.byKey(ValueKey('today-event-more-$runningId')),
            findsOneWidget,
          );
          await ec.start(runningId);
          await settle();
          // Planning's cached Event may still say pending; Today must use fresh facts.
          expect(
            find.byKey(ValueKey('today-event-more-$runningId')),
            findsNothing,
          );
          await pc.load();
          await workspace();
          expect(
            find.byKey(const ValueKey('plan-item-more-fixture-step-0')),
            findsNothing,
          );
          expect(await db.database.query('run_segments'), hasLength(1));
          await tester.pumpWidget(const SizedBox.shrink());
        });
      },
    );
  }
}
