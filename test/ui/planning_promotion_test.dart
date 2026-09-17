import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/world_node.dart';
import 'package:jax/core/entities/plan.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';
import 'package:jax/data/repositories/sqlite_planning_repository.dart';
import 'package:jax/data/repositories/sqlite_world_node_repository.dart';
import 'package:jax/ui/controllers/planning_controller.dart';
import 'package:jax/ui/pages/planning_page.dart';

import '../support/world_map_fixture.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets('promotion reference and lazy child workspace on $platform', (
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
        final plans = SqlitePlanningRepository(db);
        final worlds = SqliteWorldNodeRepository(db);
        var sequence = 100;
        final pc = PlanningController(
          planningRepository: plans,
          worldNodeRepository: worlds,
          eventRepository: SqliteEventRepository(db),
          newId: () => mapNodeId(sequence++),
          now: DateTime.now,
        );
        addTearDown(pc.dispose);
        await pc.load();
        Future<void> settle() async {
          await Future<void>.delayed(const Duration(milliseconds: 150));
          await tester.pumpAndSettle();
        }

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: platform),
            home: PlanDetailPage(controller: pc, planId: 'fixture-plan'),
          ),
        );
        await settle();
        Future<void> openPromotion() async {
          await tester.tap(
            find.byKey(const ValueKey('plan-item-more-fixture-step-0')),
          );
          await settle();
          await tester.tap(find.text('提升为世界节点'));
          await settle();
          expect(find.text('提升为世界节点？'), findsOneWidget);
        }

        final before = await db.database.query('plan_items');
        final nodesBefore = await db.database.query('world_nodes');
        await openPromotion();
        await tester.tap(find.text('取消'));
        await settle();
        expect(await db.database.query('plan_items'), before);
        expect(await db.database.query('world_nodes'), nodesBefore);
        await openPromotion();
        await tester.tap(
          find.byKey(const ValueKey('confirm-promote-plan-item')),
        );
        await settle();
        final reference = find.byKey(
          const ValueKey('plan-reference-fixture-step-0'),
        );
        expect(reference, findsOneWidget);
        expect(
          find.byKey(const ValueKey('plan-item-more-fixture-step-0')),
          findsNothing,
        );
        expect(
          tester.getTopLeft(reference).dy,
          lessThan(
            tester
                .getTopLeft(
                  find.byKey(const ValueKey('plan-item-fixture-step-1')),
                )
                .dy,
          ),
        );
        final child = pc.promotedNodeFor(pc.itemsFor('fixture-plan').first)!;
        expect(pc.currentPlanFor(child.id), isNull);
        expect(pc.projectedTodayItems.map((i) => i.id), ['fixture-step-1']);
        await tester.tap(reference);
        await settle();
        expect(find.byKey(const ValueKey('plan-item-title')), findsOneWidget);
        expect(await plans.getPlans(), hasLength(1));
        await tester.enterText(
          find.byKey(const ValueKey('plan-item-title')),
          '细化后的第一步',
        );
        await tester.tap(find.byKey(const ValueKey('add-plan-item')));
        await settle();
        expect(await plans.getPlans(), hasLength(2));
        expect(pc.projectedTodayItems.map((i) => i.title), contains('细化后的第一步'));
        expect(await db.database.query('events'), isEmpty);
        await tester.pageBack();
        await settle();
        await pc.renameWorldNode(child, '重命名后的节点');
        await settle();
        expect(
          find.descendant(of: reference, matching: find.text('重命名后的节点')),
          findsOneWidget,
        );
        await plans.setPlanStatus(
          pc.currentPlanFor(child.id)!.id,
          PlanStatus.ended,
          DateTime.now(),
        );
        await worlds.updateWorldNode(
          pc.nodeFor(child.id)!.copyWith(status: WorldNodeStatus.completed),
        );
        await plans.setPlanStatus(
          'fixture-plan',
          PlanStatus.ended,
          DateTime.now(),
        );
        await pc.load();
        await settle();
        expect(reference, findsOneWidget);
        expect(find.text('世界节点 · 已完成'), findsOneWidget);
        await tester.tap(reference);
        await settle();
        expect(find.text('重命名后的节点'), findsWidgets);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    });
  }
}
