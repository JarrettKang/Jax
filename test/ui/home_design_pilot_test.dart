import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/app.dart' show buildJaxTheme;
import 'package:jax/core/entities/category.dart' as model;
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/plan.dart';
import 'package:jax/core/entities/plan_item.dart';
import 'package:jax/core/entities/routine.dart';
import 'package:jax/core/entities/run_segment.dart';
import 'package:jax/core/entities/world_node.dart';
import 'package:jax/ui/controllers/event_controller.dart';
import 'package:jax/ui/controllers/home_view_state.dart';
import 'package:jax/ui/pages/home_page.dart';
import 'package:jax/ui/theme/home_pilot_theme.dart';
import 'package:jax/ui/widgets/execution_action_buttons.dart';
import 'package:jax/ui/widgets/world_node_ancestry_view.dart';

import '../support/home_category_fixture.dart';
import '../support/memory_repository.dart';

class _PilotPlanning extends HomeSnapshotController {
  _PilotPlanning(super.events, super.time);
  List<PlanItem> steps = [];
  @override
  List<PlanItem> itemsFor(String planId) =>
      steps.where((item) => item.planId == planId).toList();
}

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    for (final scale in [1.0, 2.0]) {
      for (final scene in [
        'root-empty',
        'root-one',
        'root-many',
        'active',
        'overdue',
        'event',
        'routine',
        'category-single',
        'category-deep',
      ]) {
        testWidgets('$scene ${platform.name} text $scale', (tester) async {
          final mobile = platform == TargetPlatform.android;
          await tester.binding.setSurfaceSize(Size(mobile ? 360 : 1200, 900));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final font = Platform.environment['JAX_PILOT_QA_FONT'];
          final icons = Platform.environment['JAX_PILOT_QA_ICONS'];
          if (icons != null) {
            await tester.runAsync(() async {
              await ui.loadFontFromList(
                File(icons).readAsBytesSync(),
                fontFamily: 'MaterialIcons',
              );
            });
          }
          if (font != null) {
            await tester.runAsync(() async {
              await ui.loadFontFromList(
                File(font).readAsBytesSync(),
                fontFamily: 'PilotQA',
              );
            });
          }
          final now = DateTime(2026, 9, 16, scene == 'overdue' ? 14 : 12);
          final repo = MemoryRepository();
          final pc = _PilotPlanning(repo, now);
          final nav = HomeNavigationState();
          var sequence = 0;
          final ec = EventController(
            repository: repo,
            newId: () => 'pilot-${sequence++}',
            now: () => now,
          );
          addTearDown(pc.dispose);
          addTearDown(nav.dispose);
          final categoryCount = scene == 'root-empty'
              ? 0
              : scene == 'root-one'
              ? 1
              : 3;
          pc.categories = [
            for (var i = 0; i < categoryCount; i++)
              model.Category(
                id: 'c$i',
                name: i == 0
                    ? '科研'
                    : i == 1
                    ? '开发项目与长期维护的工具和实验环境'
                    : '生活',
                colorKey: i,
                sortOrder: i,
                createdAt: now,
                updatedAt: now,
              ),
          ];
          pc.worldNodes = [
            for (var i = 0; i < categoryCount; i++)
              WorldNode(
                id: 'n$i',
                name: '探索退火参数',
                categoryId: 'c$i',
                status: WorldNodeStatus.inProgress,
                isFocused: true,
                sortOrder: i,
                createdAt: now,
                updatedAt: now,
              ),
          ];
          if (scene == 'root-many') {
            repo.events.add(
              JaxEvent(
                id: 'waiting',
                name: '等待反馈',
                status: EventStatus.waiting,
                createdAt: now,
                updatedAt: now,
              ),
            );
          }
          final routine = Routine(
            id: 'lunch',
            name: '吃午饭，并留出一段安静休息的时间',
            recurrence: RoutineRecurrence.daily,
            weekdayMask: 0,
            isActive: true,
            sortOrder: 0,
            createdAt: now,
            updatedAt: now,
            timeRecommendation: const RoutineTimeRecommendation(
              startMinute: 660,
              endMinute: 780,
              latestEndMinute: 1020,
            ),
          );
          if (['active', 'overdue', 'routine'].contains(scene)) {
            repo.routines.add(routine);
          }
          if (scene == 'event') {
            final start = now.subtract(const Duration(hours: 123, minutes: 45));
            repo.events.add(
              JaxEvent(
                id: 'running',
                name: '分析长时间模拟结果，检查退火过程中的结构变化与平衡性',
                status: EventStatus.running,
                firstStartedAt: start,
                createdAt: start,
                updatedAt: now,
              ),
            );
            repo.segments.add(
              RunSegment(
                id: 'segment',
                eventId: 'running',
                startedAt: start,
                createdAt: start,
              ),
            );
          }
          if (scene.startsWith('category')) {
            if (scene == 'category-deep') {
              pc.worldNodes = [
                for (var i = 0; i < 8; i++)
                  WorldNode(
                    id: 'a$i',
                    name: i == 0 ? 'snowman 粒子' : '第 $i 层：复现状态方程与长名称研究背景',
                    categoryId: i == 0 ? 'c0' : null,
                    parentWorldNodeId: i == 0 ? null : 'a${i - 1}',
                    status: WorldNodeStatus.inProgress,
                    isFocused: false,
                    sortOrder: i,
                    createdAt: now,
                    updatedAt: now,
                  ),
                pc.worldNodes.first.copyWith(parentWorldNodeId: 'a7'),
                WorldNode(
                  id: 'empty',
                  name: 'Yukawa 圆柱结构',
                  categoryId: 'c0',
                  status: WorldNodeStatus.inProgress,
                  isFocused: true,
                  sortOrder: 20,
                  createdAt: now,
                  updatedAt: now,
                ),
              ];
            }
            pc.plans = [
              Plan(
                id: 'p',
                worldNodeId: 'n0',
                status: PlanStatus.current,
                roundNumber: 1,
                createdAt: now,
                updatedAt: now,
              ),
            ];
            pc.steps = [
              for (var i = 0; i < 5; i++)
                PlanItem(
                  id: 's$i',
                  planId: 'p',
                  title: i == 0 ? '测试 1e5，比较不同退火参数下的稳定性与重复实验结果' : '分析平衡性 $i',
                  status: PlanItemStatus.next,
                  promotedWorldNodeId: i == 4 ? 'empty' : null,
                  sortOrder: i,
                  createdAt: now,
                  updatedAt: now,
                ),
            ];
            for (var i = 1; i < 3; i++) {
              repo.events.add(
                JaxEvent(
                  id: 'e$i',
                  sourcePlanItemId: 's$i',
                  name: '分析平衡性 $i',
                  status: i == 1 ? EventStatus.paused : EventStatus.waiting,
                  createdAt: now,
                  updatedAt: now,
                ),
              );
            }
            nav.selectCategory('c0');
          }
          await ec.load();
          if (scene == 'routine') {
            expect(await ec.startRoutine(routine), isNull);
          }
          final capture = GlobalKey();
          final originalTheme = buildJaxTheme(platform);
          final base = originalTheme.copyWith(
            textTheme: font == null
                ? originalTheme.textTheme
                : originalTheme.textTheme.apply(fontFamily: 'PilotQA'),
          );
          await tester.pumpWidget(
            MaterialApp(
              theme: base,
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: RepaintBoundary(
                  key: capture,
                  child: Scaffold(
                    appBar: AppBar(title: const Text('Home')),
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
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(tester.getSize(find.byType(HomePage)).height, 844);
          // The surrounding shell keeps its original theme.
          expect(
            Theme.of(tester.element(find.byType(AppBar))).colorScheme,
            base.colorScheme,
          );
          if (scene.startsWith('root')) {
            expect(find.byKey(const ValueKey('home-root-ask')), findsOneWidget);
            for (var i = 0; i < categoryCount; i++) {
              expect(
                tester
                    .getSize(find.byKey(ValueKey('home-category-entry-c$i')))
                    .height,
                greaterThanOrEqualTo(48),
              );
            }
            expect(
              find.byKey(const ValueKey('home-waiting-hint')),
              scene == 'root-many' ? findsOneWidget : findsNothing,
            );
          }
          if (['active', 'overdue'].contains(scene)) {
            expect(
              find.descendant(
                of: find.byKey(const ValueKey('home-primary-start')),
                matching: find.byType(FilledButton),
              ),
              findsOneWidget,
            );
            expect(find.byKey(const ValueKey('home-root-ask')), findsNothing);
          }
          if (['event', 'routine'].contains(scene)) {
            expect(
              find.byKey(const ValueKey('home-running-hero')),
              findsOneWidget,
            );
            if (scene == 'event') {
              expect(find.text('123:45:00'), findsOneWidget);
            }
          }
          if (scene.startsWith('category')) {
            expect(
              find.byKey(const ValueKey('home-category-plan-s4')),
              findsNothing,
            );
            expect(find.text('已暂停'), findsOneWidget);
            expect(find.text('等待中'), findsOneWidget);
            expect(find.byType(FilledButton), findsNothing);
            if (scene == 'category-deep') {
              final ancestry = tester.widget<WorldNodeAncestryView>(
                find.byType(WorldNodeAncestryView),
              );
              expect(ancestry.textStyle!.fontSize, 13);
              expect(ancestry.textStyle!.color, HomePilot.textMuted);
            }
          }
          final output = Platform.environment['JAX_PILOT_QA_DIR'];
          Future<void> captureImage(String suffix) async {
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
              File('$output/${scene}_${platform.name}_$scale$suffix.png')
                  .writeAsBytesSync(bytes);
              image.dispose();
            });
          }

          await captureImage('');
          if (scene.startsWith('category')) {
            await tester.ensureVisible(
              find.byKey(const ValueKey('home-category-start-s2')),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await captureImage('_actions');
            if (platform == TargetPlatform.windows) {
              final row = find.byKey(const ValueKey('home-category-plan-s2'));
              final before = tester.getRect(row);
              final mouse = await tester.createGesture(
                kind: PointerDeviceKind.mouse,
              );
              await mouse.addPointer(location: Offset.zero);
              await mouse.moveTo(tester.getCenter(row));
              await tester.pump();
              expect(tester.getRect(row), before);
              final box = tester.widget<ColoredBox>(
                find
                    .descendant(of: row, matching: find.byType(ColoredBox))
                    .first,
              );
              expect(box.color, HomePilot.surfaceSubtle);
              await captureImage('_hover');
              await mouse.removePointer();
            }
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pumpAndSettle();
            expect(find.byKey(const ValueKey('home-root-ask')), findsOneWidget);
          }
          if (scene == 'root-one' && platform == TargetPlatform.windows) {
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.pumpAndSettle();
            final buttonContext = tester.element(
              find.byKey(const ValueKey('home-category-entry-c0')),
            );
            final focusBorder = Theme.of(buttonContext)
                .textButtonTheme
                .style!
                .side!
                .resolve({WidgetState.focused});
            expect(
              focusBorder,
              const BorderSide(color: HomePilot.accent, width: 2),
            );
            await captureImage('_focus');
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('home-category-view')),
              findsOneWidget,
            );
          }
          await tester.pumpWidget(const SizedBox.shrink());
          ec.dispose();
        });
      }
    }
  }

  testWidgets(
    'shared execution controls retain default priority outside Home',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                ExecutionActionButton(
                  action: ExecutionAction.complete,
                  onPressed: () {},
                ),
                ExecutionActionButton(
                  action: ExecutionAction.start,
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.byType(OutlinedButton), findsOneWidget);
    },
  );
}
