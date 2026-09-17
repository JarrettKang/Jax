import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/world_node.dart';
import 'package:jax/ui/controllers/event_controller.dart';
import 'package:jax/ui/controllers/home_view_state.dart';
import 'package:jax/ui/pages/home_page.dart';
import 'package:jax/ui/widgets/world_node_ancestry_view.dart';
import 'package:jax/ui/widgets/world_node_tree_guide.dart';

import '../support/home_category_fixture.dart';
import '../support/memory_repository.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets(
      'Home ancestry is compact, complete, read-only and follows hierarchy changes $platform',
      (tester) async {
        await tester.binding.setSurfaceSize(
          Size(platform == TargetPlatform.android ? 360 : 1400, 1000),
        );
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final fontPath = Platform.environment['JAX_ANCESTRY_QA_FONT'];
        if (fontPath != null) {
          await tester.runAsync(() async {
            await ui.loadFontFromList(
              File(fontPath).readAsBytesSync(),
              fontFamily: 'AncestryQA',
            );
          });
        }
        final now = DateTime(2026, 9, 15, 17);
        final repo = MemoryRepository();
        final ec = EventController(
          repository: repo,
          newId: () => 'unused',
          now: () => now,
        );
        final pc = homeCategoryFixture(repo, now);
        final nav = HomeNavigationState();
        final names = [
          'snowman粒子',
          '复现WCA熔化',
          '复现状态方程',
          '第四层结构',
          '第五层结构',
          '第六层结构',
          '很长的祖先名称：保留完整的研究条件与物理背景以便理解上下文，不应截断或横向滚动',
          '探索退火参数',
        ];
        pc.worldNodes = [
          for (var i = 0; i < names.length; i++)
            WorldNode(
              id: 'n-$i',
              name: names[i],
              categoryId: i == 0 ? 'research' : null,
              parentWorldNodeId: i == 0 ? null : 'n-${i - 1}',
              status: WorldNodeStatus.inProgress,
              isFocused: i == names.length - 1,
              sortOrder: i,
              createdAt: now,
              updatedAt: now,
            ),
          WorldNode(
            id: 'top',
            name: '顶层研究',
            categoryId: 'research',
            status: WorldNodeStatus.inProgress,
            isFocused: true,
            sortOrder: 99,
            createdAt: now,
            updatedAt: now,
          ),
        ];
        await ec.load();
        final capture = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: capture,
            child: MaterialApp(
              theme: ThemeData(
                platform: platform,
                fontFamily: fontPath == null ? null : 'AncestryQA',
              ),
              debugShowCheckedModeBanner: false,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(1.3)),
                child: child!,
              ),
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
          ),
        );
        await tester.pumpAndSettle();
        nav.selectCategory('research');
        await tester.pumpAndSettle();
        final ancestry = find.byKey(const ValueKey('home-ancestry-n-7'));
        expect(ancestry, findsOneWidget);
        expect(find.byType(WorldNodeAncestryView), findsOneWidget);
        expect(
          find.text('科研'),
          findsOneWidget,
        ); // Category is metadata, not a parent.
        expect(find.text('探索退火参数'), findsOneWidget);
        expect(find.byKey(const ValueKey('home-ancestry-top')), findsNothing);
        expect(find.text('还没有可执行步骤'), findsNWidgets(2));
        expect(find.text('规划一下'), findsNWidgets(2));
        final beforeNodes = pc.worldNodes;
        final guides = tester
            .widgetList<WorldNodeTreeGuideFrame>(
              find.descendant(
                of: ancestry,
                matching: find.byType(WorldNodeTreeGuideFrame),
              ),
            )
            .toList();
        expect(guides, hasLength(7));
        final left = tester.getTopLeft(find.text(names.first)).dx;
        for (var i = 0; i < names.length - 1; i++) {
          expect(find.text(names[i]), findsOneWidget);
          final text = tester.widget<Text>(find.text(names[i]));
          expect(text.softWrap, isTrue);
          expect(text.maxLines, isNull);
          expect(text.overflow, isNull);
          expect(
            tester.getTopLeft(find.text(names[i])).dx - left,
            lessThanOrEqualTo(60),
          );
          if (i > 0) {
            expect(
              tester.getTopLeft(find.text(names[i])).dy,
              greaterThan(tester.getTopLeft(find.text(names[i - 1])).dy),
            );
          }
        }
        final compactText = tester.widget<Text>(find.text(names[0]));
        expect(
          compactText.style!.fontSize,
          lessThan(tester.widget<Text>(find.text('探索退火参数')).style!.fontSize!),
        );
        expect(guides.last.guideColor, isNotNull);
        expect(
          find.descendant(of: ancestry, matching: find.byType(Card)),
          findsNothing,
        );
        expect(
          find.descendant(of: ancestry, matching: find.byType(InkWell)),
          findsNothing,
        );
        expect(
          find.descendant(of: ancestry, matching: find.byType(GestureDetector)),
          findsNothing,
        );
        expect(
          tester
              .getSize(find.byKey(const ValueKey('home-category-group-n-7')))
              .width,
          lessThanOrEqualTo(820),
        );
        expect(tester.takeException(), isNull);
        // Optional visual QA artifacts, no user data involved.
        final output = Platform.environment['JAX_ANCESTRY_QA_DIR'];
        if (output != null) {
          await tester.runAsync(() async {
            final boundary =
                capture.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final img = await boundary.toImage();
            final bytes = (await img.toByteData(
              format: ui.ImageByteFormat.png,
            ))!.buffer.asUint8List();
            Directory(output).createSync(recursive: true);
            File('$output/home_ancestry_${platform.name}.png')
                .writeAsBytesSync(bytes);
            img.dispose();
          });
        }
        await tester.tap(find.text(names[0]));
        await tester.pumpAndSettle();
        expect(nav.categoryId, 'research');
        expect(pc.worldNodes, beforeNodes);
        expect(repo.events, isEmpty);
        pc.worldNodes = [
          for (final n in pc.worldNodes)
            n.id == 'n-0' ? n.copyWith(name: '祖先已改名') : n,
        ];
        await pc.load();
        await tester.pumpAndSettle();
        expect(find.text('祖先已改名'), findsOneWidget);
        expect(find.text(names[0]), findsNothing);
        // Move to a different real parent with the SAME NAME as the Category.
        pc.worldNodes = [
          for (final n in pc.worldNodes)
            n.id == 'top'
                ? n.copyWith(name: '科研', isFocused: false)
                : n.id == 'n-7'
                ? n.copyWith(parentWorldNodeId: 'top')
                : n,
        ];
        await pc.load();
        await tester.pumpAndSettle();
        expect(
          find.text('科研'),
          findsNWidgets(2),
        ); // Do not trim by name equality.
        expect(
          tester
              .widget<WorldNodeAncestryView>(find.byType(WorldNodeAncestryView))
              .names,
          ['科研'],
        );
        expect(find.text('祖先已改名'), findsNothing);
        pc.categories = [pc.categories.single.copyWith(name: '研究领域')];
        await pc.load();
        await tester.pumpAndSettle();
        expect(find.text('研究领域'), findsOneWidget);
        expect(find.text('科研'), findsOneWidget);
        // Make the current node top-level: no empty tree, label or spacing stub.
        pc.worldNodes = [
          for (final n in pc.worldNodes)
            n.id == 'n-7'
                ? n.copyWith(parentWorldNodeId: null, categoryId: 'research')
                : n,
        ];
        await pc.load();
        await tester.pumpAndSettle();
        expect(find.byType(WorldNodeAncestryView), findsNothing);
        expect(find.text('无上级节点'), findsNothing);
        expect(find.text('暂无路径'), findsNothing);
        expect(find.text('探索退火参数'), findsOneWidget);
        expect(find.text('还没有可执行步骤'), findsOneWidget);
        expect(nav.categoryId, 'research');
        expect(repo.events, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        ec.dispose();
        pc.dispose();
        nav.dispose();
      },
    );
  }
}
