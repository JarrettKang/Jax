import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:jax/ui/theme/planning_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/app.dart' show buildJaxTheme;
import 'package:jax/core/entities/category.dart' as model;
import 'package:jax/core/entities/plan.dart';
import 'package:jax/core/entities/plan_item.dart';
import 'package:jax/core/entities/plan_review_note.dart';
import 'package:jax/core/entities/world_node.dart';
import 'package:jax/ui/pages/planning_page.dart';
import 'package:jax/ui/theme/home_pilot_theme.dart';
import 'package:jax/ui/widgets/world_node_ancestry_view.dart';
import 'package:jax/ui/widgets/world_node_tree_guide.dart';

import '../support/home_category_fixture.dart';
import '../support/memory_repository.dart';

class _PlanningSnapshot extends HomeSnapshotController {
  _PlanningSnapshot(super.events, super.time);
  List<PlanItem> steps = [];
  List<PlanReviewNote> reviews = [];
  @override
  List<PlanItem> itemsFor(String id) =>
      steps.where((s) => s.planId == id).toList();
  @override
  List<PlanReviewNote> reviewNotesFor(String id) =>
      reviews.where((r) => r.planId == id).toList();
}

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    for (final scale in [1.0, 2.0]) {
      for (final scene in [
        'overview-one',
        'overview-many',
        'workspace-short',
        'workspace-deep',
        'workspace-empty',
      ]) {
        testWidgets('$scene ${platform.name} scale $scale', (tester) async {
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.binding.setSurfaceSize(
            Size(platform == TargetPlatform.android ? 360 : 1200, 900),
          );
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final font = Platform.environment['JAX_PLANNING_QA_FONT'];
          final icons = Platform.environment['JAX_PLANNING_QA_ICONS'];
          await tester.runAsync(() async {
            if (font != null) {
              await ui.loadFontFromList(
                File(font).readAsBytesSync(),
                fontFamily: 'PlanningQA',
              );
            }
            if (icons != null) {
              await ui.loadFontFromList(
                File(icons).readAsBytesSync(),
                fontFamily: 'MaterialIcons',
              );
            }
          });
          final time = DateTime(2026, 9, 16, 14);
          final pc = _PlanningSnapshot(MemoryRepository(), time);
          addTearDown(pc.dispose);
          final deep = scene.endsWith('deep') || scene.endsWith('many');
          pc.categories = [
            model.Category(
              id: 'science',
              name: '科研',
              sortOrder: 0,
              createdAt: time,
              updatedAt: time,
            ),
          ];
          pc.worldNodes = [
            if (deep)
              for (var i = 0; i < 8; i++)
                WorldNode(
                  id: 'a$i',
                  name: '层级 $i：复现状态方程与实验条件',
                  parentWorldNodeId: i == 0 ? null : 'a${i - 1}',
                  categoryId: i == 0 ? 'science' : null,
                  status: WorldNodeStatus.inProgress,
                  isFocused: false,
                  sortOrder: i,
                  createdAt: time,
                  updatedAt: time,
                ),
            WorldNode(
              id: 'work',
              name: deep ? '探索退火参数，研究长期演化中结构变化与平衡性的联系' : '探索退火参数',
              parentWorldNodeId: deep ? 'a7' : null,
              categoryId: deep ? null : 'science',
              status: WorldNodeStatus.inProgress,
              isFocused: true,
              sortOrder: 9,
              createdAt: time,
              updatedAt: time,
            ),
            WorldNode(
              id: 'linked',
              name: '关联世界节点的当前名称',
              categoryId: 'science',
              status: WorldNodeStatus.inProgress,
              isFocused: scene == 'overview-many',
              sortOrder: 10,
              createdAt: time,
              updatedAt: time,
            ),
          ];
          if (scene != 'workspace-empty') {
            pc.plans = [
              Plan(
                id: 'plan',
                worldNodeId: 'work',
                status: PlanStatus.current,
                roundNumber: 1,
                createdAt: time,
                updatedAt: time,
              ),
            ];
            pc.steps = [
              for (final (i, status) in [
                PlanItemStatus.next,
                PlanItemStatus.dispatched,
                PlanItemStatus.done,
                PlanItemStatus.dropped,
                PlanItemStatus.next,
              ].indexed)
                PlanItem(
                  id: 's$i',
                  planId: 'plan',
                  title: i == 0
                      ? '比较不同退火参数下的稳定性与重复实验结果'
                      : i == 4
                      ? '过时的引用名称'
                      : '分析平衡性 $i',
                  status: status,
                  promotedWorldNodeId: i == 4 ? 'linked' : null,
                  sortOrder: i,
                  createdAt: time,
                  updatedAt: time,
                ),
            ];
            pc.reviews = [
              PlanReviewNote(
                id: 'review',
                planId: 'plan',
                content: '记录实验观察：继续比较边界条件，下一轮需要控制样本数量。',
                createdAt: time,
                updatedAt: time,
              ),
            ];
          }
          final capture = GlobalKey();
          final base = buildJaxTheme(platform);
          await tester.pumpWidget(
            RepaintBoundary(
              key: capture,
              child: MaterialApp(
                theme: font == null
                    ? base
                    : base.copyWith(
                        textTheme: base.textTheme.apply(
                          fontFamily: 'PlanningQA',
                        ),
                      ),
                home: Builder(
                  builder: (context) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: scene.startsWith('overview')
                        ? PlanningPage(controller: pc)
                        : PlanDetailPage(controller: pc, worldNodeId: 'work'),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.byType(Card), findsNothing);
          expect(find.text('└ '), findsNothing);
          expect(find.text('草稿'), findsNothing);
          expect(find.text('过时的引用名称'), findsNothing);
          expect(find.byType(WorldNodeAncestryView), findsWidgets);
          final ancestry = tester
              .widgetList<WorldNodeAncestryView>(
                find.byType(WorldNodeAncestryView),
              )
              .first;
          expect(ancestry.textStyle!.fontSize, 13);
          expect(ancestry.guideColor, HomePilot.hairlineStrong);
          if (deep) {
            expect(
              ancestry.names,
              containsAll([for (var i = 0; i < 8; i++) '层级 $i：复现状态方程与实验条件']),
            );
          }
          if (scene.startsWith('workspace')) {
            expect(ancestry.names, isNot(contains(pc.nodeFor('work')!.name)));
            expect(
              tester
                  .widget<Text>(
                    find.byKey(const ValueKey('planning-workspace-title')),
                  )
                  .style!
                  .fontSize,
              26,
            );
          }
          Future<void> captureFrame(String label) async {
            expect(tester.takeException(), isNull);
            final output = Platform.environment['JAX_PLANNING_QA_DIR'];
            if (output == null) return;
            await tester.runAsync(() async {
              final boundary =
                  capture.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final image = await boundary.toImage();
              final bytes = (await image.toByteData(
                format: ui.ImageByteFormat.png,
              ))!.buffer.asUint8List();
              Directory(output).createSync(recursive: true);
              File('$output/${scene}_${platform.name}_${scale}_$label.png')
                  .writeAsBytesSync(bytes);
              image.dispose();
            });
          }

          Future<void> reveal(Key key) async {
            await tester.scrollUntilVisible(
              find.byKey(key),
              240,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.pumpAndSettle();
            await tester.ensureVisible(find.byKey(key));
            await tester.pumpAndSettle();
          }

          await captureFrame('initial');
          if (scene == 'overview-one' && platform == TargetPlatform.windows) {
            final row = find.byKey(const ValueKey('focused-world-node-work'));
            final bounds = tester.getRect(row);
            final mouse = await tester.createGesture(
              kind: PointerDeviceKind.mouse,
            );
            await mouse.addPointer(location: Offset.zero);
            await mouse.moveTo(tester.getCenter(row));
            await tester.pump();
            expect(tester.getRect(row), bounds);
            final decoration =
                tester
                        .widget<DecoratedBox>(
                          find
                              .descendant(
                                of: row,
                                matching: find.byType(DecoratedBox),
                              )
                              .first,
                        )
                        .decoration
                    as BoxDecoration;
            expect(decoration.color, HomePilot.surfaceSubtle);
            await captureFrame('hover');
            await mouse.removePointer();
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.pumpAndSettle();
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.pumpAndSettle();
            final focusDecoration =
                tester
                        .widget<DecoratedBox>(
                          find
                              .descendant(
                                of: row,
                                matching: find.byType(DecoratedBox),
                              )
                              .first,
                        )
                        .decoration
                    as BoxDecoration;
            expect(
              focusDecoration.border,
              Border.all(color: HomePilot.accent, width: 2),
            );
            expect(tester.getRect(row), bounds);
            await captureFrame('focus');
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            await tester.pumpAndSettle();
            expect(find.byKey(const ValueKey('plan-detail')), findsOneWidget);
            await tester.pageBack();
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('planning-overview')),
              findsOneWidget,
            );
          }
          if (scene == 'workspace-short' || scene == 'workspace-deep') {
            await reveal(const ValueKey('draft-edit-s0'));
            final before = tester.getTopLeft(find.text(pc.steps.first.title));
            await tester.tap(find.byKey(const ValueKey('draft-edit-s0')));
            await tester.pumpAndSettle();
            final editor = tester.widget<TextField>(
              find.byKey(const ValueKey('draft-title-s0')),
            );
            expect(editor.style!.fontSize, 16);
            expect(editor.decoration!.focusedBorder!.borderSide.width, 2);
            expect(
              tester
                  .getTopLeft(find.byKey(const ValueKey('draft-title-s0')))
                  .dx,
              lessThanOrEqualTo(before.dx),
            );
            await captureFrame('inline');
            if (platform == TargetPlatform.android) {
              tester.view.viewInsets = const FakeViewPadding(bottom: 300);
              addTearDown(tester.view.resetViewInsets);
              await tester.pumpAndSettle();
              await Scrollable.ensureVisible(
                tester.element(find.byKey(const ValueKey('save-draft-s0'))),
                alignment: 1,
              );
              await tester.pumpAndSettle();
              expect(
                tester
                    .getBottomRight(find.byKey(const ValueKey('save-draft-s0')))
                    .dy,
                lessThanOrEqualTo(600),
              );
              await captureFrame('inline-keyboard');
              tester.view.resetViewInsets();
              await tester.pumpAndSettle();
            }
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pumpAndSettle();
            expect(find.byKey(const ValueKey('draft-title-s0')), findsNothing);
            await reveal(const ValueKey('plan-item-more-s3'));
            expect(
              tester
                  .getSize(find.byKey(const ValueKey('plan-item-more-s3')))
                  .height,
              greaterThanOrEqualTo(48),
            );
            expect(
              find.descendant(
                of: find.byKey(const ValueKey('plan-item-s3')),
                matching: find.byType(Opacity),
              ),
              findsNothing,
            );
            await tester.tap(find.byKey(const ValueKey('plan-item-more-s3')));
            await tester.pumpAndSettle();
            expect(find.text('恢复计划步骤'), findsOneWidget);
            await captureFrame('dropped-menu');
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pumpAndSettle();
            await reveal(const ValueKey('plan-reference-s4'));
            expect(find.text('关联世界节点的当前名称'), findsOneWidget);
            expect(
              find.ancestor(
                of: find.byKey(const ValueKey('plan-reference-s4')),
                matching: find.byType(PlanningRowSurface),
              ),
              findsOneWidget,
            );
            pc.worldNodes = [
              for (final n in pc.worldNodes)
                n.id == 'linked' ? n.copyWith(name: '引用目标已改名') : n,
            ];
            await pc.load();
            await tester.pumpAndSettle();
            expect(find.text('引用目标已改名'), findsOneWidget);
            await reveal(const ValueKey('plan-item-title'));
            await tester.tap(find.byKey(const ValueKey('plan-item-title')));
            await tester.pumpAndSettle();
            await tester.ensureVisible(
              find.byKey(const ValueKey('add-plan-item')),
            );
            await tester.pumpAndSettle();
            expect(find.byKey(const ValueKey('add-plan-item')), findsOneWidget);
            await tester.tap(find.byKey(const ValueKey('add-plan-item')));
            await tester.pumpAndSettle();
            expect(find.text('写下一步再添加'), findsOneWidget);
            await captureFrame('quick-add-error');
            if (platform == TargetPlatform.android) {
              tester.view.viewInsets = const FakeViewPadding(bottom: 300);
              await tester.pumpAndSettle();
              await Scrollable.ensureVisible(
                tester.element(find.byKey(const ValueKey('add-plan-item'))),
                alignment: 1,
              );
              await tester.pumpAndSettle();
              expect(
                tester
                    .getBottomRight(find.byKey(const ValueKey('add-plan-item')))
                    .dy,
                lessThanOrEqualTo(600),
              );
              await captureFrame('quick-add-keyboard');
              tester.view.resetViewInsets();
              await tester.pumpAndSettle();
            }
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pumpAndSettle();
            await reveal(const ValueKey('add-review-note'));
            final reviewToggle = find.textContaining('上次记录：');
            await tester.ensureVisible(reviewToggle);
            await tester.pumpAndSettle();
            await tester.tap(reviewToggle);
            await tester.pumpAndSettle();
            await tester.ensureVisible(
              find.byKey(const ValueKey('review-note-review')),
            );
            await tester.pumpAndSettle();
            await captureFrame('review');
          }
          if (deep && scene.startsWith('overview')) {
            expect(find.byType(WorldNodeTreeGuideFrame), findsWidgets);
          }
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }
}
