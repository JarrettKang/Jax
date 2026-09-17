import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/app.dart' show buildJaxTheme;
import 'package:jax/core/entities/category.dart' as model;
import 'package:jax/core/entities/world_node.dart';
import 'package:jax/core/preferences/world_category_collapse_store.dart';
import 'package:jax/ui/pages/world_page.dart';
import 'package:jax/ui/theme/home_pilot_theme.dart';
import 'package:jax/ui/theme/world_theme.dart';
import 'package:jax/ui/widgets/world_node_browsing_row.dart';

import '../support/home_category_fixture.dart';
import '../support/memory_repository.dart';

void main() {
  for (final (platform, width) in [
    (TargetPlatform.android, 320.0),
    (TargetPlatform.android, 390.0),
    (TargetPlatform.windows, 480.0),
    (TargetPlatform.windows, 1400.0),
  ]) {
    for (final scale in [1.0, 2.0]) {
      for (final scene in ['single', 'tree', 'deep']) {
        testWidgets('World $scene ${platform.name} $width scale $scale', (
          tester,
        ) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 900);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.binding.setSurfaceSize(Size(width, 900));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final font = Platform.environment['JAX_WORLD_FONT'];
          final icons = Platform.environment['JAX_WORLD_ICONS'];
          await tester.runAsync(() async {
            for (final (family, file) in [
              ('WorldQA', font),
              ('MaterialIcons', icons),
            ]) {
              if (file != null) {
                await ui.loadFontFromList(
                  File(file).readAsBytesSync(),
                  fontFamily: family,
                );
              }
            }
          });
          final time = DateTime(2026, 9, 16);
          final pc = HomeSnapshotController(MemoryRepository(), time);
          addTearDown(pc.dispose);
          pc.categories = [
            model.Category(
              id: 'research',
              name: scene == 'deep' ? '科研与长期项目：需要保持完整可读的结构分区名称' : '科研',
              sortOrder: 0,
              createdAt: time,
              updatedAt: time,
            ),
            if (scene != 'single')
              model.Category(
                id: 'life',
                name: '生活',
                sortOrder: 1,
                createdAt: time,
                updatedAt: time,
              ),
          ];
          WorldNode node(
            String id,
            String name, {
            String? parent,
            bool focused = false,
            bool completed = false,
            int order = 0,
          }) => WorldNode(
            id: id,
            name: name,
            parentWorldNodeId: parent,
            categoryId: parent == null ? 'research' : null,
            status: completed
                ? WorldNodeStatus.completed
                : WorldNodeStatus.inProgress,
            isFocused: focused,
            sortOrder: order,
            createdAt: time,
            updatedAt: time,
          );
          pc.worldNodes = [
            node('root', '研究结构与实验条件', focused: true),
            if (scene != 'single') ...[
              node('leaf', '一个普通节点', parent: 'root', focused: true),
              node('done', '完成的父节点', parent: 'root', completed: true, order: 1),
              node(
                'doneLeaf',
                '完成后仍可阅读的历史节点\n保留完整结构名称',
                parent: 'done',
                completed: true,
              ),
              node('restored', '恢复后未关注的普通节点', parent: 'root', order: 2),
            ],
            if (scene == 'deep') ...[
              for (var i = 0; i < 8; i++)
                node(
                  'd$i',
                  i == 7 ? '很深的结构名称仍然自然换行，而不是只剩下狭窄的文字列' : '结构层级 ${i + 2}',
                  parent: i == 0 ? 'root' : 'd${i - 1}',
                  order: 3,
                ),
              node('deepSibling', '深层兄弟节点', parent: 'd6', order: 4),
            ],
          ];
          final boundary = GlobalKey();
          final base = buildJaxTheme(platform);
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: font == null
                    ? base
                    : base.copyWith(
                        textTheme: base.textTheme.apply(fontFamily: 'WorldQA'),
                      ),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: WorldPage(
                  controller: pc,
                  worldCategoryCollapseStore:
                      InMemoryWorldCategoryCollapseStore(),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.byType(Card), findsNothing);
          await capture(
            tester,
            boundary,
            '$scene-${platform.name}-${width.toInt()}-$scale',
          );
          Future<void> visible(String id) async {
            await tester.ensureVisible(
              find.byKey(ValueKey('world-node-more-$id')),
            );
            await tester.pumpAndSettle();
          }

          Future<void> menu(String id) async {
            await visible(id);
            await tester.tap(find.byKey(ValueKey('world-node-more-$id')));
            await tester.pumpAndSettle();
          }

          if (scene == 'deep') {
            await visible('d7');
            final row = tester.widget<WorldNodeBrowsingRow>(
              find.byKey(const ValueKey('world-node-d7')),
            );
            expect(row.indent, width == 320 && scale == 2 ? 16 : 48);
            final title = find.text(pc.nodeFor('d7')!.name);
            expect(tester.widget<Text>(title).maxLines, isNull);
            expect(tester.getSize(title).width, greaterThan(100));
            expect(find.text('第 9 层 · 上层：结构层级 8'), findsNWidgets(2));
            await capture(
              tester,
              boundary,
              'deep-end-${platform.name}-${width.toInt()}-$scale',
            );
            await menu('d7');
            expect(find.text('移动到…'), findsOneWidget);
            await tester.tap(find.text('移动到…'));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await capture(
              tester,
              boundary,
              'move-${platform.name}-${width.toInt()}-$scale',
            );
            await tester.tap(find.text('取消'));
            await tester.pumpAndSettle();
          }
          if (scene == 'tree') {
            await visible('done');
            await tester.tap(find.text('完成的父节点'));
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('world-node-doneLeaf')),
              findsNothing,
            );
            await tester.tap(find.text('完成的父节点'));
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('world-node-doneLeaf')),
              findsOneWidget,
            );
            final completedText = tester.widget<Text>(
              find.text(pc.nodeFor('doneLeaf')!.name),
            );
            expect(
              completedText.style!.decoration,
              isNot(TextDecoration.lineThrough),
            );
            for (final action in ['重命名', '添加子节点']) {
              await menu('root');
              await tester.tap(find.text(action));
              await tester.pumpAndSettle();
              await tester.enterText(
                find.byType(TextFormField),
                '自然换行的名称输入，不改变原有保存流程',
              );
              await tester.pumpAndSettle();
              if (platform == TargetPlatform.android) {
                tester.view.viewInsets = const FakeViewPadding(bottom: 300);
                await tester.pumpAndSettle();
                expect(tester.takeException(), isNull);
                await tester.ensureVisible(
                  find.widgetWithText(FilledButton, '保存'),
                );
                await tester.pumpAndSettle();
                expect(
                  tester
                      .getBottomRight(find.widgetWithText(FilledButton, '保存'))
                      .dy,
                  lessThanOrEqualTo(600),
                );
                await capture(
                  tester,
                  boundary,
                  'keyboard-${width.toInt()}-$scale',
                );
                tester.view.resetViewInsets();
                await tester.pumpAndSettle();
              }

              expect(tester.takeException(), isNull);
              await capture(
                tester,
                boundary,
                'edit-${action == '重命名' ? 'rename' : 'add'}-${platform.name}-${width.toInt()}-$scale',
              );
              await tester.tap(find.text('取消'));
              await tester.pumpAndSettle();
            }
            await tester.ensureVisible(
              find.byKey(const ValueKey('world-category-more-research')),
            );
            await tester.pumpAndSettle();
            await tester.tap(
              find.byKey(const ValueKey('world-category-more-research')),
            );
            await tester.pumpAndSettle();
            await tester.tap(find.text('删除分类'));
            await tester.pumpAndSettle();
            expect(find.text('删除分类？'), findsOneWidget);
            await capture(
              tester,
              boundary,
              'delete-${platform.name}-${width.toInt()}-$scale',
            );
            await tester.tap(find.text('取消'));
            await tester.pumpAndSettle();
          }
          if (platform == TargetPlatform.windows && scene == 'tree') {
            await visible('root');
            final main = find.byKey(const ValueKey('world-node-main-root'));
            final rect = tester.getRect(main);
            final pointer = await tester.createGesture(
              kind: PointerDeviceKind.mouse,
            );
            await pointer.addPointer(location: Offset.zero);
            await pointer.moveTo(rect.center);
            await tester.pumpAndSettle();
            expect(tester.getRect(main), rect);
            final gesture = find
                .descendant(of: main, matching: find.byType(GestureDetector))
                .first;
            Focus.of(tester.element(gesture)).requestFocus();
            await tester.pumpAndSettle();
            final surface = find.descendant(
              of: main,
              matching: find.byType(WorldRowSurface),
            );
            final container = tester.widget<Container>(
              find
                  .descendant(of: surface, matching: find.byType(Container))
                  .first,
            );
            expect(
              ((container.foregroundDecoration as BoxDecoration).border!
                      as Border)
                  .top
                  .color,
              HomePilot.accent,
            );
            expect(pc.nodeFor('root')!.isFocused, isTrue);
            await capture(tester, boundary, 'focus-${width.toInt()}-$scale');
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            await tester.pumpAndSettle();
            expect(find.byKey(const ValueKey('world-node-leaf')), findsNothing);
            await tester.sendKeyEvent(LogicalKeyboardKey.space);
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('world-node-leaf')),
              findsOneWidget,
            );
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.pumpAndSettle();
            await pointer.removePointer();
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}

Future<void> capture(
  WidgetTester tester,
  GlobalKey boundary,
  String name,
) async {
  final dir = Platform.environment['JAX_WORLD_CAPTURE_DIR'];
  if (dir == null) return;
  await tester.runAsync(() async {
    final image =
        await (boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(dir).create(recursive: true);
    await File('$dir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
