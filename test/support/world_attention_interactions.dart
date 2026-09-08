import 'dart:ui' show PointerDeviceKind, SemanticsAction, SemanticsActionEvent;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/world_node.dart';
import 'package:jax/core/preferences/world_category_collapse_store.dart';
import 'package:jax/core/use_cases/dispatch_plan_items.dart';
import 'package:jax/core/use_cases/start_event.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';
import 'package:jax/data/repositories/sqlite_planning_repository.dart';
import 'package:jax/ui/controllers/planning_controller.dart';
import 'package:jax/ui/pages/world_node_detail_page.dart';
import 'package:jax/ui/widgets/world_node_tree_guide.dart';

import 'world_map_fixture.dart';

Future<void> seedWorldAttentionFixture(AppDatabase app) async {
  await seedWorldMapFixture(app);
  // A leaf owns the current plan; parent attention remains a valid domain state.
  await app.database.update('plans', {'world_node_id': mapNodeId(2)});
  await app.database.update('world_nodes', {'is_focused': 0});
  await app.database.update(
    'world_nodes',
    {'is_focused': 1},
    where: 'id = ?',
    whereArgs: [mapNodeId(2)],
  );
  await app.database.update(
    'world_nodes',
    {'status': 'completed'},
    where: 'id IN (?, ?)',
    whereArgs: [mapNodeId(8), mapNodeId(10)],
  );
  final now = DateTime(2026, 9, 8, 12);
  final events = await DispatchPlanItems(
    repository: SqlitePlanningRepository(app),
    newId: () => '50000000-0000-4000-8000-000000000001',
    now: () => now,
  )(['fixture-step-1']);
  await StartEvent(
    repository: SqliteEventRepository(app),
    newId: () => '50000000-0000-4000-8000-000000000002',
    now: () => now,
  )(events.single.id);
}

// These helpers run inside real-async SQLite tests or a native test binding.
Future<void> settleWorldAttention(WidgetTester tester) async {
  await Future<void>.delayed(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
}

Future<void> exerciseWorldAttention(
  WidgetTester tester,
  AppDatabase app,
  PlanningController controller,
  WorldCategoryCollapseStore store, {
  bool desktop = false,
}) async {
  final kind = desktop ? PointerDeviceKind.mouse : PointerDeviceKind.touch;
  Finder main(int id) =>
      find.byKey(ValueKey('world-node-main-${mapNodeId(id)}'));
  Finder button(String name, int id) =>
      find.byKey(ValueKey('world-node-$name-${mapNodeId(id)}'));
  bool focused(int id) => controller.nodeFor(mapNodeId(id))!.isFocused;
  bool expanded(int id) => tester
      .widget<WorldNodeTreeGuideFrame>(button('guide', id))
      .hasExpandedChildren;
  Future<void> visible(int id) async {
    await tester.ensureVisible(main(id));
    await tester.pumpAndSettle();
  }

  // Whole rows, not just counts: attention must never rewrite execution facts.
  final tables = [
    'categories',
    'plans',
    'plan_items',
    'events',
    'event_day_plans',
    'run_segments',
    'sync_tombstones',
  ];
  final facts = {
    for (final table in tables) table: await app.database.query(table),
  };
  final nodeFacts = await app.database.query('world_nodes');

  Future<void> tap(int id) async {
    await visible(id);
    await tester.tap(main(id), kind: kind);
    await settleWorldAttention(tester);
    expect(find.byType(WorldNodeDetailPage), findsNothing);
  }

  Future<void> attentionMenu(int id, bool value) async {
    await visible(id);
    final before = await store.loadCollapsedSectionKeys();
    final oldFocus = focused(id);
    await tester.tap(button('more', id), kind: kind);
    await tester.pumpAndSettle();
    expect(focused(id), oldFocus);
    expect(find.text('查看当前计划'), findsNothing);
    expect(find.text('查看详情'), findsOneWidget);
    await tester.tap(find.text(value ? '关注' : '取消关注'));
    await settleWorldAttention(tester);
    expect(focused(id), value);
    expect(await store.loadCollapsedSectionKeys(), before);
  }

  await visible(1);
  await tester.tap(main(1), kind: kind);
  // Check the very next frame: no timer advance or double-click window.
  await tester.pump();
  expect(expanded(1), isFalse);
  expect(focused(1), isFalse);
  await attentionMenu(1, true);
  await tap(1);
  expect(expanded(1), isTrue);
  expect(focused(1), isTrue);
  await tap(1);
  expect(expanded(1), isFalse);
  expect(focused(1), isTrue);
  await attentionMenu(1, false);
  await tester.tap(button('branch', 1), kind: kind);
  await tester.pump();
  expect(expanded(1), isTrue);
  expect(focused(1), isFalse);

  await tap(0); // Leaf with no current plan still appears in Planning.
  expect(focused(0), isTrue);
  expect(
    controller.focusedWorldNodePlanning
        .singleWhere((v) => v.node.id == mapNodeId(0))
        .currentPlan,
    isNull,
  );
  await tap(0);
  expect(focused(0), isFalse);

  expect(
    controller.recommendationGroups.single.items.single.id,
    'fixture-step-0',
  );
  await tap(2);
  expect(focused(2), isFalse);
  expect(controller.recommendationGroups, isEmpty);
  await tap(2);
  expect(focused(2), isTrue);
  expect(
    controller.recommendationGroups.single.items.single.id,
    'fixture-step-0',
  );
  expect(
    controller.focusedWorldNodePlanning.single.currentPlan!.id,
    'fixture-plan',
  );
  expect(
    find.descendant(of: main(2), matching: find.byTooltip('关注中')),
    findsOneWidget,
  );
  await attentionMenu(2, false);
  expect(controller.recommendationGroups, isEmpty);
  await attentionMenu(2, true);

  await tap(8); // Completed parent remains browsable.
  expect(expanded(8), isFalse);
  await tap(8);
  expect(expanded(8), isTrue);
  expect(controller.nodeFor(mapNodeId(8))!.status, WorldNodeStatus.completed);
  await tap(9);
  expect(focused(9), isFalse);
  expect(controller.nodeFor(mapNodeId(9))!.status, WorldNodeStatus.completed);

  await visible(0);
  final beforeDrag = await store.loadCollapsedSectionKeys();
  await tester.drag(main(0), const Offset(0, -150));
  await settleWorldAttention(tester);
  expect(focused(0), isFalse);
  expect(await store.loadCollapsedSectionKeys(), beforeDrag);

  await visible(1);
  final semantics = tester.ensureSemantics();
  await tester.pump();
  Future<void> activate(int id) async {
    await visible(id);
    final node = tester.getSemantics(main(id));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    tester.binding.performSemanticsAction(
      SemanticsActionEvent(
        viewId: tester.view.viewId,
        nodeId: node.id,
        type: SemanticsAction.tap,
      ),
    );
    await settleWorldAttention(tester);
  }

  await activate(1);
  expect(expanded(1), isFalse);
  expect(focused(1), isFalse);
  await activate(1);
  expect(expanded(1), isTrue);
  await activate(0);
  expect(focused(0), isTrue);
  await activate(0);
  expect(focused(0), isFalse);
  await visible(9);
  expect(
    tester
        .getSemantics(main(9))
        .getSemanticsData()
        .hasAction(SemanticsAction.tap),
    isFalse,
  );
  semantics.dispose();
  await visible(1);

  if (desktop) {
    final gesture = find
        .descendant(
          of: button('more', 1),
          matching: find.byType(GestureDetector),
        )
        .first;
    Focus.of(tester.element(gesture)).requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('关注'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(expanded(1), isTrue);
    expect(focused(1), isFalse);
  }
  for (final table in tables) {
    expect(await app.database.query(table), facts[table], reason: table);
  }
  final afterNodes = await app.database.query('world_nodes');
  Map<String, Object?> withoutTimestamp(Map<String, Object?> row) =>
      Map.of(row)..remove('updated_at_utc');
  expect(afterNodes.map(withoutTimestamp), nodeFacts.map(withoutTimestamp));
  expect(tester.takeException(), isNull);
}
