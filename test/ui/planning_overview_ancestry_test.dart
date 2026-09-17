import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';
import 'package:jax/data/repositories/sqlite_planning_repository.dart';
import 'package:jax/data/repositories/sqlite_world_node_repository.dart';
import 'package:jax/ui/controllers/planning_controller.dart';
import 'package:jax/ui/pages/planning_page.dart';

import '../support/world_map_fixture.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets(
      'overview shows full ancestry without Plan metadata $platform',
      (tester) async {
        await tester.runAsync(() async {
          await tester.binding.setSurfaceSize(
            Size(platform == TargetPlatform.android ? 360 : 1400, 1000),
          );
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final db = await AppDatabase.inMemory();
          addTearDown(db.close);
          await seedWorldMapFixture(db);
          final plans = SqlitePlanningRepository(db);
          final worlds = SqliteWorldNodeRepository(db);
          await worlds.setWorldNodeFocus(mapNodeId(3), false, DateTime.now());
          await worlds.setWorldNodeFocus(mapNodeId(14), true, DateTime.now());
          await plans.createPlan(
            id: 'deep-plan',
            worldNodeId: mapNodeId(14),
            now: DateTime.now(),
          );
          await plans.createPlanItem(
            id: 'deep-item',
            planId: 'deep-plan',
            title: '不应显示的步骤摘要',
            now: DateTime.now(),
          );
          final pc = PlanningController(
            planningRepository: plans,
            worldNodeRepository: worlds,
            eventRepository: SqliteEventRepository(db),
            newId: () => 'unused',
            now: DateTime.now,
          );
          addTearDown(pc.dispose);
          await pc.load();
          final before = <String, Object?>{};
          for (final table in [
            'world_nodes',
            'plans',
            'plan_items',
            'events',
            'sync_tombstones',
          ]) {
            before[table] = await db.database.query(table);
          }
          Future<void> settle() async {
            await Future<void>.delayed(const Duration(milliseconds: 150));
            await tester.pumpAndSettle();
          }

          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(platform: platform),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(1.3)),
                child: child!,
              ),
              home: PlanningPage(controller: pc),
            ),
          );
          await settle();
          final node = pc.nodeFor(mapNodeId(14))!;
          expect(find.text(node.name), findsOneWidget);
          for (final ancestor
              in pc.pathFor(node).where((n) => n.id != node.id)) {
            expect(find.text(ancestor.name), findsOneWidget);
          }
          expect(find.text('科研'), findsOneWidget);
          for (final metadata in [
            '第 1 轮计划',
            '未执行步骤',
            '已派发',
            '已完成',
            '不应显示的步骤摘要',
          ]) {
            expect(find.textContaining(metadata), findsNothing);
          }
          expect(find.byIcon(Icons.visibility_outlined), findsNothing);
          expect(find.byIcon(Icons.chevron_right), findsOneWidget);
          expect(find.byType(Card), findsNothing);
          final title = tester.widget<Text>(find.text(node.name));
          final ancestry = tester.widget<Text>(find.text('科研'));
          expect(
            title.style!.fontSize!,
            greaterThan(ancestry.style!.fontSize!),
          );
          final tile = find.byKey(ValueKey('focused-world-node-${node.id}'));
          expect(tester.getSize(tile).width, lessThanOrEqualTo(780));
          expect(tester.takeException(), isNull);
          await tester.tap(tile);
          await settle();
          expect(find.byKey(const ValueKey('plan-detail')), findsOneWidget);
          expect(find.text('不应显示的步骤摘要'), findsOneWidget);
          for (final entry in before.entries) {
            expect(
              await db.database.query(entry.key),
              entry.value,
              reason: entry.key,
            );
          }
          await tester.pumpWidget(const SizedBox.shrink());
        });
      },
    );
  }
}
