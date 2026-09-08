import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/preferences/world_category_collapse_store.dart';
import 'package:jax/ui/pages/world_node_detail_page.dart';
import 'package:jax/ui/widgets/world_node_tree_guide.dart';

import 'world_map_fixture.dart';

/// Shared by narrow/wide widget coverage and native platform fixture tests.
Future<void> exerciseWorldTreeBrowsing(
  WidgetTester tester,
  WorldCategoryCollapseStore store, {
  bool keyboard = false,
}) async {
  Finder row(int id) => find.byKey(ValueKey('world-node-${mapNodeId(id)}'));
  Finder action(String kind, int id) =>
      find.byKey(ValueKey('world-node-$kind-${mapNodeId(id)}'));
  Future<void> tapName(int id) async {
    await tester.ensureVisible(row(id));
    await tester.pumpAndSettle();
    // The title, away from the chevron and More, is the large browsing target.
    await tester.tap(
      find.descendant(of: row(id), matching: find.byType(Text)).first,
    );
    await tester.pumpAndSettle();
    expect(find.byType(WorldNodeDetailPage), findsNothing);
  }

  await tapName(1);
  expect(row(2), findsNothing);
  expect(row(3), findsNothing);
  expect(
    await store.loadCollapsedSectionKeys(),
    contains(WorldCategoryCollapseStore.branchKey(mapNodeId(1))),
  );
  expect(
    tester
        .widget<WorldNodeTreeGuideFrame>(action('guide', 1))
        .hasExpandedChildren,
    isFalse,
  );
  await tapName(1);
  expect(row(2), findsOneWidget);
  expect(row(4), findsOneWidget);
  await tester.tap(action('branch', 1));
  await tester.pumpAndSettle();
  expect(row(2), findsNothing); // One chevron click toggles exactly once.
  await tester.tap(action('branch', 1));
  await tester.pumpAndSettle();
  expect(row(2), findsOneWidget);

  await tapName(3); // Focused parent with a current Plan still toggles.
  expect(row(4), findsNothing);
  final beforeLeaf = await store.loadCollapsedSectionKeys();
  await tapName(2);
  expect(await store.loadCollapsedSectionKeys(), beforeLeaf);
  expect(row(4), findsNothing);
  expect(tester.widget<ListTile>(row(2)).onTap, isNull);

  await tester.ensureVisible(row(1));
  await tester.pumpAndSettle();
  await tester.tap(action('more', 1));
  await tester.pumpAndSettle();
  expect(row(2), findsOneWidget);
  expect(
    tester
        .widget<PopupMenuItem<String>>(find.byType(PopupMenuItem<String>).first)
        .value,
    'open-detail',
  );
  await tester.tapAt(const Offset(2, 2));
  await tester.pumpAndSettle();
  expect(row(2), findsOneWidget);
  expect(await store.loadCollapsedSectionKeys(), beforeLeaf);

  // Deep parent hit target and connector refresh, then leaf Detail round-trip.
  await tapName(17);
  expect(row(14), findsNothing);
  expect(
    tester
        .widget<WorldNodeTreeGuideFrame>(action('guide', 17))
        .hasExpandedChildren,
    isFalse,
  );
  await tapName(17);
  expect(row(14), findsOneWidget);
  await tester.ensureVisible(row(14));
  await tester.pumpAndSettle();
  await tapName(14);
  final scroll = tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byKey(const ValueKey('world-node-overview')),
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position;
  final offset = scroll.pixels;
  final beforeDetail = await store.loadCollapsedSectionKeys();
  await tester.tap(action('more', 14));
  await tester.pumpAndSettle();
  await tester.tap(find.text('查看详情'));
  await tester.pumpAndSettle();
  expect(
    tester
        .widget<WorldNodeDetailPage>(find.byType(WorldNodeDetailPage))
        .worldNodeId,
    mapNodeId(14),
  );
  expect(find.text('概览'), findsOneWidget);
  await tester.pageBack();
  await tester.pumpAndSettle();
  expect(scroll.pixels, offset);
  expect(await store.loadCollapsedSectionKeys(), beforeDetail);
  expect(row(4), findsNothing);
  expect(row(14), findsOneWidget);

  if (keyboard) {
    await tester.ensureVisible(row(1));
    await tester.pumpAndSettle();
    final ink = find
        .descendant(of: row(1), matching: find.byType(InkWell))
        .first;
    final focusChild = find
        .descendant(of: ink, matching: find.byType(GestureDetector))
        .first;
    Focus.of(tester.element(focusChild)).requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(row(2), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(row(2), findsOneWidget);
  }
}
