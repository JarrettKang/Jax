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

Future<void> doubleTapWorld(
  WidgetTester tester,
  Finder target, {
  PointerDeviceKind kind = PointerDeviceKind.touch,
  int intervalMs = 110,
  VoidCallback? betweenTaps,
}) async {
  await tester.tap(target, kind: kind);
  await Future<void>.delayed(Duration(milliseconds: intervalMs));
  await tester.pump();
  betweenTaps?.call();
  await tester.tap(target, kind: kind);
  await settleWorldAttention(tester);
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

  Future<void> double(int id, {int interval = 110}) async {
    await visible(id);
    final before = await store.loadCollapsedSectionKeys();
    final wasExpanded = expanded(id);
    await doubleTapWorld(
      tester,
      main(id),
      kind: kind,
      intervalMs: interval,
      betweenTaps: () => expect(expanded(id), wasExpanded),
    );
    expect(expanded(id), wasExpanded);
    expect(await store.loadCollapsedSectionKeys(), before);
    expect(find.byType(WorldNodeDetailPage), findsNothing);
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

  await visible(1);
  await tester.tap(main(1), kind: kind);
  await settleWorldAttention(tester);
  expect(expanded(1), isFalse);
  expect(focused(1), isFalse);
  await double(1);
  expect(focused(1), isTrue);
  expect(
    controller.focusedWorldNodePlanning
        .singleWhere((v) => v.node.id == mapNodeId(1))
        .currentPlan,
    isNull,
  );
  await double(1, interval: 220);
  expect(focused(1), isFalse);
  await tester.tap(button('branch', 1), kind: kind);
  await tester.pumpAndSettle();
  expect(expanded(1), isTrue);
  await double(1);
  expect(focused(1), isTrue);
  await double(1);
  expect(focused(1), isFalse);

  await visible(2);
  await tester.tap(main(2), kind: kind);
  await settleWorldAttention(tester);
  expect(focused(2), isFalse);
  await double(2);
  expect(focused(2), isTrue);
  await double(2);
  expect(focused(2), isFalse);

  await double(9); // Completed leaf neither restores nor focuses.
  expect(focused(9), isFalse);
  expect(controller.nodeFor(mapNodeId(9))!.status, WorldNodeStatus.completed);
  await visible(1);
  await doubleTapWorld(
    tester,
    button('branch', 1),
    kind: kind,
    betweenTaps: () => expect(expanded(1), isFalse),
  );
  expect(expanded(1), isTrue);
  expect(focused(1), isFalse);

  await visible(3);
  expect(
    controller.recommendationGroups.single.items.single.id,
    'fixture-step-0',
  );
  await double(3);
  expect(controller.recommendationGroups, isEmpty);
  expect(controller.focusedWorldNodePlanning, isEmpty);
  await double(3);
  expect(
    controller.recommendationGroups.single.items.single.id,
    'fixture-step-0',
  );
  expect(
    controller.focusedWorldNodePlanning.single.currentPlan!.id,
    'fixture-plan',
  );
  expect(
    find.descendant(of: main(3), matching: find.byTooltip('关注中')),
    findsOneWidget,
  );

  final beforeMore = await store.loadCollapsedSectionKeys();
  await tester.tap(button('more', 3), kind: kind);
  await tester.pumpAndSettle();
  expect(find.text('查看当前计划'), findsNothing);
  expect(find.text('查看详情'), findsOneWidget);
  expect(expanded(3), isTrue);
  expect(focused(3), isTrue);
  await tester.tap(find.text('取消关注'));
  await settleWorldAttention(tester);
  expect(focused(3), isFalse);
  expect(controller.recommendationGroups, isEmpty);
  await tester.tap(button('more', 3));
  await tester.pumpAndSettle();
  await tester.tap(find.text('关注'));
  await settleWorldAttention(tester);
  expect(focused(3), isTrue);
  expect(await store.loadCollapsedSectionKeys(), beforeMore);

  // Scroll wins the gesture arena; no single or double row mutation follows.
  await visible(1);
  final beforeDrag = await store.loadCollapsedSectionKeys();
  await tester.drag(main(1), const Offset(0, -150));
  await settleWorldAttention(tester);
  expect(focused(1), isFalse);
  expect(await store.loadCollapsedSectionKeys(), beforeDrag);

  // Accessibility tap bypasses pointer double-tap recognition: browse only.
  await visible(1);
  final semantics = tester.ensureSemantics();
  await tester.pump();
  final parentSemantics = tester.getSemantics(main(1));
  expect(
    parentSemantics.getSemanticsData().hasAction(SemanticsAction.tap),
    isTrue,
  );
  tester.binding.performSemanticsAction(
    SemanticsActionEvent(
      viewId: tester.view.viewId,
      nodeId: parentSemantics.id,
      type: SemanticsAction.tap,
    ),
  );
  await tester.pumpAndSettle();
  expect(expanded(1), isFalse);
  expect(focused(1), isFalse);
  tester.binding.performSemanticsAction(
    SemanticsActionEvent(
      viewId: tester.view.viewId,
      nodeId: tester.getSemantics(main(1)).id,
      type: SemanticsAction.tap,
    ),
  );
  await tester.pumpAndSettle();
  expect(expanded(1), isTrue);
  expect(
    tester
        .getSemantics(main(2))
        .getSemanticsData()
        .hasAction(SemanticsAction.tap),
    isFalse,
  );
  semantics.dispose();

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
