import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/plan.dart';
import 'package:jax/core/entities/plan_item.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/preferences/sqlite_world_category_collapse_store.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';
import 'package:jax/data/repositories/sqlite_planning_repository.dart';
import 'package:jax/data/repositories/sqlite_world_node_repository.dart';
import 'package:jax/ui/controllers/planning_controller.dart';
import 'package:jax/ui/pages/planning_page.dart';
import 'package:jax/ui/pages/world_page.dart';

import '../support/world_map_fixture.dart';

Future<void> settle(WidgetTester tester) async {
  await Future<void>.delayed(const Duration(milliseconds: 200));
  await tester.pumpAndSettle();
}

void main() {
  test(
    'first step rolls back both rows on failure and rejects ended history',
    () async {
      final app = await AppDatabase.inMemory();
      addTearDown(app.close);
      await seedWorldMapFixture(app);
      final repo = SqlitePlanningRepository(app);
      await expectLater(
        repo.createFirstPlanningStep(
          planId: 'first',
          itemId: 'fixture-step-0',
          worldNodeId: mapNodeId(0),
          title: 'fails duplicate id',
          now: DateTime.now(),
        ),
        throwsA(anything),
      );
      expect(await repo.getPlan('first'), isNull);
      final old = await repo.createPlan(
        id: 'old',
        worldNodeId: mapNodeId(0),
        now: DateTime.now(),
      );
      await repo.setPlanStatus(old.id, PlanStatus.ended, DateTime.now());
      await expectLater(
        repo.createFirstPlanningStep(
          planId: 'new',
          itemId: 'new-item',
          worldNodeId: mapNodeId(0),
          title: 'no automatic iteration',
          now: DateTime.now(),
        ),
        throwsA(anything),
      );
      expect(await repo.getPlan('new'), isNull);
    },
  );
  for (final width in [390.0, 1200.0]) {
    testWidgets('deep workspace and twelve steps fit $width', (tester) async {
      await tester.runAsync(() async {
        await tester.binding.setSurfaceSize(Size(width, 850));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final app = await AppDatabase.inMemory();
        addTearDown(app.close);
        await seedWorldMapFixture(app);
        final repo = SqlitePlanningRepository(app);
        final plan = await repo.createPlan(
          id: 'deep',
          worldNodeId: mapNodeId(14),
          now: DateTime.now(),
        );
        for (var i = 0; i < 12; i++) {
          await repo.createPlanItem(
            id: 'deep-$i',
            planId: plan.id,
            title: '步骤 $i：检查计算结果与研究假设',
            now: DateTime.now(),
          );
        }
        final c = PlanningController(
          planningRepository: repo,
          worldNodeRepository: SqliteWorldNodeRepository(app),
          eventRepository: SqliteEventRepository(app),
          newId: () => 'unused',
          now: DateTime.now,
        );
        addTearDown(c.dispose);
        await c.load();
        await tester.pumpWidget(
          MaterialApp(
            home: PlanDetailPage(controller: c, planId: plan.id),
          ),
        );
        await settle(tester);
        for (final name in [
          '科研',
          'A：多层结构',
          'D：下一分支',
          'E：第三层',
          'F：第四层',
          'G：第五层',
        ]) {
          expect(find.text(name), findsOneWidget);
        }
        expect(find.text('12 个步骤'), findsOneWidget);
        expect(find.text('计划步骤'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('plan-item-title')),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          find.byKey(const ValueKey('plan-item-initial-status')),
          findsNothing,
        );
        await tester.tap(find.byKey(const ValueKey('plan-item-title')));
        await settle(tester);
        expect(
          find.byKey(const ValueKey('plan-item-initial-status')),
          findsOneWidget,
        );
        expect(find.text('还没有复盘记录'), findsNothing);
        expect(tester.takeException(), isNull);
        expect(c.itemsFor(plan.id), hasLength(12));
        await tester.pumpWidget(const SizedBox());
      });
    });
    testWidgets(
      'World direct workspace, no navigation writes and continuous entry $width',
      (tester) async {
        await tester.runAsync(() async {
          await tester.binding.setSurfaceSize(Size(width, 850));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final app = await AppDatabase.inMemory();
          addTearDown(app.close);
          await seedWorldMapFixture(app);
          var sequence = 0;
          final c = PlanningController(
            planningRepository: SqlitePlanningRepository(app),
            worldNodeRepository: SqliteWorldNodeRepository(app),
            eventRepository: SqliteEventRepository(app),
            newId: () => 'flow-${sequence++}',
            now: DateTime.now,
          );
          addTearDown(c.dispose);
          await c.load();
          final facts = {
            for (final t in [
              'plans',
              'plan_items',
              'events',
              'event_day_plans',
              'run_segments',
              'sync_tombstones',
            ])
              t: await app.database.query(t),
          };
          await tester.pumpWidget(
            MaterialApp(
              home: WorldPage(
                controller: c,
                worldCategoryCollapseStore: SqliteWorldCategoryCollapseStore(
                  app,
                ),
              ),
            ),
          );
          await settle(tester);
          await tester.tap(
            find.byKey(ValueKey('world-node-main-${mapNodeId(0)}')),
          );
          await settle(tester);
          expect(find.text('开始规划'), findsOneWidget);
          expect(find.byType(PlanDetailPage), findsNothing);
          await tester.tap(find.text('开始规划'));
          await settle(tester);
          expect(find.byType(PlanDetailPage), findsOneWidget);
          expect(find.byType(AlertDialog), findsNothing);
          final input = find.byKey(const ValueKey('plan-item-title'));
          await tester.enterText(input, '未提交');
          await tester.tap(find.text('取消'));
          await settle(tester);
          for (final t in facts.keys) {
            expect(await app.database.query(t), facts[t], reason: t);
          }
          await tester.enterText(input, '   ');
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await settle(tester);
          expect(c.currentPlanFor(mapNodeId(0)), isNull);
          for (final title in ['检查数据', '检查数据', '重新画图']) {
            await tester.enterText(input, title);
            await tester.testTextInput.receiveAction(TextInputAction.done);
            await settle(tester);
            expect(tester.widget<TextField>(input).controller!.text, isEmpty);
            expect(tester.widget<TextField>(input).focusNode!.hasFocus, isTrue);
          }
          final plan = c.currentPlanFor(mapNodeId(0))!;
          expect(c.itemsFor(plan.id).map((i) => i.title), [
            '检查数据',
            '检查数据',
            '重新画图',
          ]);
          expect(c.itemsFor(plan.id).map((i) => i.sortOrder), [0, 1, 2]);
          expect(
            c.itemsFor(plan.id).every((i) => i.status == PlanItemStatus.draft),
            isTrue,
          );
          await tester.tap(
            find.byKey(const ValueKey('plan-item-initial-status')),
          );
          await tester.enterText(input, '检查平衡性');
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await settle(tester);
          expect(c.itemsFor(plan.id).last.status, PlanItemStatus.next);
          expect(
            c.recommendationGroups.any(
              (g) => g.items.any((i) => i.title == '检查平衡性'),
            ),
            isTrue,
          );
          for (final t in [
            'events',
            'event_day_plans',
            'run_segments',
            'sync_tombstones',
          ]) {
            expect(await app.database.query(t), facts[t], reason: t);
          }
          expect(find.byType(AlertDialog), findsNothing);
          await c.setPlanStatus(plan, PlanStatus.ended);
          await settle(tester);
          expect(find.text('上一轮已结束'), findsOneWidget);
          expect(input, findsNothing);
          expect(
            c.plans.where((p) => p.worldNodeId == mapNodeId(0)),
            hasLength(1),
          );
          await tester.tap(find.byKey(const ValueKey('start-planning-round')));
          await settle(tester);
          expect(c.currentPlanFor(mapNodeId(0))!.roundNumber, 2);
          expect(input, findsOneWidget);
          expect(c.itemsFor(plan.id), hasLength(4));
          await tester.pumpWidget(
            MaterialApp(
              key: UniqueKey(),
              home: PlanDetailPage(controller: c, planId: plan.id),
            ),
          );
          await settle(tester);
          expect(input, findsNothing);
          expect(find.byKey(const ValueKey('add-review-note')), findsOneWidget);
          await tester.pumpWidget(const SizedBox());
        });
      },
    );
  }
}
