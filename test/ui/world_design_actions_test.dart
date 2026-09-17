import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/app.dart' show buildJaxTheme;
import 'package:jax/core/entities/world_node.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/preferences/sqlite_world_category_collapse_store.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';
import 'package:jax/data/repositories/sqlite_planning_repository.dart';
import 'package:jax/data/repositories/sqlite_world_node_repository.dart';
import 'package:jax/ui/controllers/planning_controller.dart';
import 'package:jax/ui/pages/world_page.dart';

import '../support/world_map_fixture.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets(
      'World migrated dialogs save, validate, restore and preserve category children ${platform.name}',
      (tester) async {
        await tester.runAsync(() async {
          await tester.binding.setSurfaceSize(
            Size(platform == TargetPlatform.android ? 390 : 1200, 900),
          );
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final db = await AppDatabase.inMemory();
          addTearDown(db.close);
          await seedWorldMapFixture(db);
          var sequence = 0;
          final pc = PlanningController(
            planningRepository: SqlitePlanningRepository(db),
            worldNodeRepository: SqliteWorldNodeRepository(db),
            eventRepository: SqliteEventRepository(db),
            newId: () =>
                '60000000-0000-4000-8000-${(++sequence).toString().padLeft(12, '0')}',
            now: () => DateTime(2026, 9, 16, 12),
          );
          addTearDown(pc.dispose);
          await pc.load();
          final facts = {
            for (final table in [
              'plans',
              'plan_items',
              'events',
              'run_segments',
              'dataset_metadata',
            ])
              table: await db.database.query(table),
          };
          await tester.pumpWidget(
            MaterialApp(
              theme: buildJaxTheme(platform),
              home: WorldPage(
                controller: pc,
                worldCategoryCollapseStore: SqliteWorldCategoryCollapseStore(
                  db,
                ),
              ),
            ),
          );
          Future<void> settle() async {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            await tester.pumpAndSettle();
          }

          await settle();
          Future<void> action(String id, String label) async {
            final button = find.byKey(ValueKey('world-node-more-$id'));
            await tester.ensureVisible(button);
            await tester.pumpAndSettle();
            await tester.tap(button);
            await tester.pumpAndSettle();
            await tester.tap(find.text(label));
            await settle();
          }

          final parentId = mapNodeId(1);
          await action(parentId, '关注');
          ScaffoldMessenger.of(
            tester.element(find.byKey(const ValueKey('world-node-overview'))),
          ).removeCurrentSnackBar();
          await tester.pumpAndSettle();
          await action(parentId, '重命名');
          await tester.enterText(find.byType(TextFormField), '重命名后仍是原结构节点');
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await settle();
          expect(pc.nodeFor(parentId)!.name, '重命名后仍是原结构节点');
          expect(pc.nodeFor(parentId)!.isFocused, isTrue);
          await action(parentId, '添加子节点');
          await tester.enterText(find.byType(TextFormField), '新增结构分支');
          await tester.tap(find.text('保存'));
          await settle();
          final child = pc.worldNodes.singleWhere((n) => n.name == '新增结构分支');
          expect(child.parentWorldNodeId, parentId);
          expect(child.isFocused, isFalse);
          expect(child.categoryId, isNull);
          await action(parentId, '添加子节点');
          await tester.tap(find.text('保存'));
          await settle();
          expect(find.textContaining('世界节点名称不能为空'), findsOneWidget);
          await action(parentId, '完成节点');
          expect(pc.nodeFor(parentId)!.status, WorldNodeStatus.completed);
          expect(pc.nodeFor(parentId)!.isFocused, isFalse);
          await action(parentId, '恢复节点');
          expect(pc.nodeFor(parentId)!.status, WorldNodeStatus.inProgress);
          expect(pc.nodeFor(parentId)!.isFocused, isFalse);
          expect(
            find.descendant(
              of: find.byKey(ValueKey('world-node-main-$parentId')),
              matching: find.byTooltip('关注中'),
            ),
            findsNothing,
          );
          final categoryMenu = find.byKey(
            const ValueKey('world-category-more-research'),
          );
          await tester.ensureVisible(categoryMenu);
          await tester.pumpAndSettle();
          await tester.tap(categoryMenu);
          await tester.pumpAndSettle();
          await tester.tap(find.text('删除分类'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('取消'));
          await settle();
          expect(pc.categories.any((c) => c.id == 'research'), isTrue);
          await tester.tap(categoryMenu);
          await tester.pumpAndSettle();
          await tester.tap(find.text('删除分类'));
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(FilledButton, '删除'));
          await settle();
          expect(pc.categories.any((c) => c.id == 'research'), isFalse);
          expect(pc.nodeFor(mapNodeId(1))!.categoryId, isNull);
          expect(pc.nodeFor(child.id)!.parentWorldNodeId, parentId);
          for (final entry in facts.entries) {
            expect(
              await db.database.query(entry.key),
              entry.value,
              reason: entry.key,
            );
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        });
      },
    );
  }
}
