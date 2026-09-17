import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/category.dart' as entity;
import 'package:jax/core/entities/world_node.dart';
import 'package:jax/ui/controllers/event_controller.dart';
import 'package:jax/ui/controllers/home_view_state.dart';
import 'package:jax/ui/pages/home_page.dart';

import '../support/home_category_fixture.dart';
import '../support/memory_repository.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets(
      'Dynamic categories inherit World identity, order and changes $platform',
      (tester) async {
        await tester.binding.setSurfaceSize(
          Size(platform == TargetPlatform.android ? 360 : 1200, 800),
        );
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final now = DateTime(2026, 9, 15, 10);
        final repo = MemoryRepository();
        final ec = EventController(
          repository: repo,
          newId: () => 'unused',
          now: () => now,
        );
        final pc = homeCategoryFixture(repo, now);
        final nav = HomeNavigationState();

        addTearDown(pc.dispose);
        addTearDown(nav.dispose);
        entity.Category category(String id, String name, int order) =>
            entity.Category(
              id: id,
              name: name,
              sortOrder: order,
              createdAt: now,
              updatedAt: now,
            );
        WorldNode node(
          String id,
          String? categoryId, {
          String? parent,
          bool focused = true,
          WorldNodeStatus status = WorldNodeStatus.inProgress,
        }) => WorldNode(
          id: id,
          name: id,
          categoryId: categoryId,
          parentWorldNodeId: parent,
          status: status,
          isFocused: focused,
          sortOrder: 0,
          createdAt: now,
          updatedAt: now,
        );
        pc.categories = [
          category('dev', '开发项目', 0),
          pc.categories.single,
          category('life', '生活', 2),
        ];
        pc.worldNodes = [
          node('科研根', 'research', focused: false),
          node('科研 A', null, parent: '科研根'),
          node('科研 B', null, parent: '科研根'),
          node('开发 C', 'dev'),
          node('无分类事项', null),
          node('生活事项', 'life', focused: false),
          node('已完成节点', 'life', status: WorldNodeStatus.completed),
        ];
        await ec.load();
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: platform),
            home: Scaffold(
              body: HomePage(
                controller: ec,
                planningController: pc,
                navigation: nav,
                now: () => now,
                onOpenEvents: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        Finder entry(String? id) =>
            find.byKey(ValueKey('home-category-entry-$id'));
        expect(homeCategoryEntries(pc).map((c) => c?.id), [
          'dev',
          'research',
          null,
        ]);
        expect(find.text('科研'), findsOneWidget);
        expect(find.text('其他'), findsOneWidget);
        expect(find.text('工作'), findsNothing);
        expect(find.text('未分类'), findsNothing);
        expect(find.text('生活'), findsNothing);
        expect(find.textContaining('·'), findsNothing);
        expect(
          tester.getTopLeft(entry('dev')).dy,
          lessThan(tester.getTopLeft(entry('research')).dy),
        );
        expect(tester.getSize(entry('dev')).width, lessThan(300));
        await tester.tap(entry('research'));
        await tester.pumpAndSettle();
        expect(find.text('科研 A'), findsOneWidget);
        expect(find.text('科研 B'), findsOneWidget);
        expect(find.text('开发 C'), findsNothing);
        expect(find.text('科研根'), findsNWidgets(2));
        expect(
          find.byKey(const ValueKey('home-category-group-科研根')),
          findsNothing,
        );
        expect(find.text('还没有可执行步骤'), findsNWidgets(2));
        expect(find.text('规划一下'), findsNWidgets(2));
        expect(repo.events, isEmpty);
        expect(pc.plans, isEmpty);
        pc.categories = [
          pc.categories[1].copyWith(name: '科学探索', sortOrder: 0),
          pc.categories[0].copyWith(sortOrder: 1),
          pc.categories[2],
        ];
        await pc.load();
        await tester.pumpAndSettle();
        expect(find.text('科学探索'), findsOneWidget);
        if (platform == TargetPlatform.android) {
          await tester.binding.handlePopRoute();
        } else {
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        }
        await tester.pumpAndSettle();
        expect(
          tester.getTopLeft(entry('research')).dy,
          lessThan(tester.getTopLeft(entry('dev')).dy),
        );
        // Last focused research nodes disappear; a no-plan life node appears.
        pc.worldNodes = [
          for (final n in pc.worldNodes)
            n.copyWith(
              isFocused: n.id == '科研 A' || n.id == '科研 B'
                  ? false
                  : n.id == '生活事项'
                  ? true
                  : n.isFocused,
            ),
        ];
        await pc.load();
        await tester.pumpAndSettle();
        expect(entry('research'), findsNothing);
        expect(entry('life'), findsOneWidget);
        await tester.tap(entry('life'));
        await tester.pumpAndSettle();
        // Category deletion: nodes resolve into the UI-only Other group.
        pc.categories = pc.categories.where((c) => c.id != 'life').toList();
        await pc.load();
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('home-root-ask')), findsOneWidget);
        expect(nav.categorySelected, isFalse);
        await tester.tap(entry(null));
        await tester.pumpAndSettle();
        expect(find.text('无分类事项'), findsOneWidget);
        expect(find.text('生活事项'), findsOneWidget);
        expect(find.text('已完成节点'), findsNothing);
        expect(pc.categories.map((c) => c.name), isNot(contains('其他')));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        ec.dispose();
      },
    );

    testWidgets(
      'Each category preserves its own scroll and empty context safely returns $platform',
      (tester) async {
        await tester.binding.setSurfaceSize(
          Size(platform == TargetPlatform.android ? 360 : 1200, 700),
        );
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final now = DateTime(2026, 9, 15, 10);
        final repo = MemoryRepository();
        final ec = EventController(
          repository: repo,
          newId: () => 'unused',
          now: () => now,
        );
        final pc = homeCategoryFixture(repo, now);
        final nav = HomeNavigationState();

        addTearDown(pc.dispose);
        addTearDown(nav.dispose);
        pc.worldNodes = [
          for (var i = 0; i < 16; i++)
            WorldNode(
              id: 'node-$i',
              name: '事项 $i',
              categoryId: i < 12 ? 'research' : null,
              status: WorldNodeStatus.inProgress,
              isFocused: true,
              sortOrder: i,
              createdAt: now,
              updatedAt: now,
            ),
        ];
        await ec.load();
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: platform),
            home: Scaffold(
              body: HomePage(
                controller: ec,
                planningController: pc,
                navigation: nav,
                now: () => now,
                onOpenEvents: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        nav.selectCategory('research');
        await tester.pumpAndSettle();
        final researchScroll = find.byKey(
          const PageStorageKey('home-category-scroll-research'),
        );
        await tester.drag(researchScroll, const Offset(0, -400));
        await tester.pumpAndSettle();
        final saved = nav.categoryOffsets['research']!;
        expect(saved, greaterThan(100));
        nav.back();
        await tester.pumpAndSettle();
        nav.selectCategory(null);
        await tester.pumpAndSettle();
        final otherScroll = tester.state<ScrollableState>(
          find.descendant(
            of: find.byKey(const PageStorageKey('home-category-scroll-null')),
            matching: find.byType(Scrollable),
          ),
        );
        expect(otherScroll.position.pixels, 0);
        nav.back();
        await tester.pumpAndSettle();
        nav.selectCategory('research');
        await tester.pumpAndSettle();
        expect(
          tester
              .state<ScrollableState>(
                find.descendant(
                  of: researchScroll,
                  matching: find.byType(Scrollable),
                ),
              )
              .position
              .pixels,
          closeTo(saved, 1),
        );
        // Loading/error must not discard a context based on an incomplete snapshot.
        pc.loading = true;
        pc.worldNodes = [];
        await pc.load();
        await tester.pumpAndSettle();
        expect(nav.categorySelected, isTrue);
        pc.loading = false;
        pc.error = StateError('offline');
        await pc.load();
        await tester.pumpAndSettle();
        expect(nav.categorySelected, isTrue);
        pc.error = null;
        await pc.load();
        await tester.pumpAndSettle();
        expect(nav.categorySelected, isFalse);
        expect(find.byKey(const ValueKey('home-root-ask')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        ec.dispose();
      },
    );
  }
}
