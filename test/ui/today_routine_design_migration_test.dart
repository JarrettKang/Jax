import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/app.dart' show buildJaxTheme;
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/jax_day.dart';
import 'package:jax/core/entities/plan.dart';
import 'package:jax/core/entities/plan_item.dart';
import 'package:jax/core/entities/world_node.dart';
import 'package:jax/core/entities/routine.dart';
import 'package:jax/core/entities/routine_category.dart';
import 'package:jax/core/entities/run_segment.dart';
import 'package:jax/core/preferences/routine_category_collapse_store.dart';
import 'package:jax/ui/controllers/event_controller.dart';
import 'package:jax/ui/pages/events_page.dart';
import 'package:jax/ui/pages/routine_page.dart';
import 'package:jax/ui/widgets/execution_row_shell.dart';
import 'package:jax/ui/theme/home_pilot_theme.dart';

import '../support/home_category_fixture.dart';
import '../support/memory_repository.dart';

class _PlanningFixture extends HomeSnapshotController {
  _PlanningFixture(super.events, super.time);
  @override
  List<PlanItem> get projectedTodayItems => [
    PlanItem(
      id: 'step',
      planId: 'plan',
      title: '验证长期实验参数与退火条件，保留完整的计划行动名称',
      status: PlanItemStatus.next,
      sortOrder: 0,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    ),
  ];
}

void main() {
  for (final (platform, width) in [
    (TargetPlatform.android, 320.0),
    (TargetPlatform.android, 390.0),
    (TargetPlatform.windows, 480.0),
    (TargetPlatform.windows, 1400.0),
  ]) {
    for (final scale in [1.0, 2.0]) {
      for (final scene in [
        'today-mixed',
        'today-event',
        'today-routine',
        'today-night',
        'routine',
        'routine-running',
      ]) {
        testWidgets('Phase C $scene ${platform.name} $width $scale', (
          tester,
        ) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 1000);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          final font = Platform.environment['JAX_C_FONT'];
          await tester.runAsync(() async {
            for (final (family, path) in [
              ('PhaseCQA', font),
              ('MaterialIcons', Platform.environment['JAX_C_ICONS']),
            ]) {
              if (path != null) {
                await ui.loadFontFromList(
                  File(path).readAsBytesSync(),
                  fontFamily: family,
                );
              }
            }
          });
          final now = scene == 'today-night'
              ? DateTime(2026, 9, 16, 23, 30)
              : DateTime(2026, 9, 16, 12);
          final repo = MemoryRepository([
            for (final (id, status) in [
              ('pending', EventStatus.pending),
              ('paused', EventStatus.paused),
              ('waiting', EventStatus.waiting),
              if (scene == 'today-event') ('running', EventStatus.running),
            ])
              JaxEvent(
                id: id,
                name: '$id：这是需要保持完整可读的临时事项名称',
                status: status,
                createdAt: now,
                updatedAt: now,
              ),
          ]);
          if (scene == 'today-event') {
            repo.segments.add(
              RunSegment(
                id: 'segment',
                eventId: 'running',
                startedAt: now.subtract(const Duration(minutes: 23)).toUtc(),
                createdAt: now.toUtc(),
              ),
            );
          }
          repo.routineCategories.add(
            RoutineCategory(
              id: 'life',
              name: '生活与长期习惯：完整分类名称',
              sortOrder: 0,
              colorKey: 3,
              createdAt: now,
              updatedAt: now,
            ),
          );
          Routine r(
            String id,
            String name, {
            RoutineType type = RoutineType.scheduled,
            RoutineTimeRecommendation? window,
            bool quick = false,
          }) => Routine(
            id: id,
            name: name,
            routineCategoryId: 'life',
            type: type,
            recurrence: RoutineRecurrence.daily,
            weekdayMask: 0,
            isActive: true,
            sortOrder: repo.routines.length,
            createdAt: now,
            updatedAt: now,
            timeRecommendation: window,
            showInHomeQuickActions: quick,
          );
          repo.routines.addAll([
            r(
              'active',
              '午饭：现在需要处理',
              window: const RoutineTimeRecommendation(
                startMinute: 660,
                endMinute: 780,
                latestEndMinute: 1020,
              ),
            ),
            r(
              'overdue',
              '已超过理想时间的长名称日常，需要注意最晚完成时间',
              window: const RoutineTimeRecommendation(
                startMinute: 600,
                endMinute: 660,
                latestEndMinute: 840,
              ),
            ),
            r(
              'active2',
              '另一项当前日常',
              window: const RoutineTimeRecommendation(
                startMinute: 690,
                endMinute: 750,
                latestEndMinute: 900,
              ),
            ),
            r(
              'later',
              '晚饭：稍后进入推荐期',
              window: const RoutineTimeRecommendation(
                startMinute: 1050,
                endMinute: 1140,
                latestEndMinute: 1200,
              ),
            ),
            r('ordinary', '没有时间窗口的持续日常'),
            r('rp', '暂停中的日常：状态变化仍是同一个执行行'),
            r('rw', '等待中的日常：不把等待表现为警告'),
            r('done', '已完成的日常'),
            r(
              'night',
              '跨午夜的晚上洗漱',
              window: const RoutineTimeRecommendation(
                startMinute: 1350,
                endMinute: 30,
                latestEndMinute: 120,
              ),
            ),
            r('demand', '按需整理思路', type: RoutineType.onDemand, quick: true),
            if ((scene == 'today-routine' || scene == 'routine-running'))
              r('rr', '正在执行的日常'),
          ]);
          final day = JaxDay.containing(now).key;
          for (final (id, status) in [
            ('rp', RoutineExecutionStatus.paused),
            ('rw', RoutineExecutionStatus.waiting),
            ('done', RoutineExecutionStatus.completed),
            if ((scene == 'today-routine' || scene == 'routine-running'))
              ('rr', RoutineExecutionStatus.running),
          ]) {
            repo.routineExecutions.add(
              RoutineExecution(
                id: 'ex-$id',
                routineId: id,
                occurrenceDate: day,
                status: status,
                createdAt: now.toUtc(),
                updatedAt: now.toUtc(),
                completedAt: status == RoutineExecutionStatus.completed
                    ? now.toUtc()
                    : null,
              ),
            );
            if (id == 'rr') {
              repo.routineSegments.add(
                RoutineRunSegment(
                  id: 'rseg',
                  executionId: 'ex-rr',
                  startedAt: now.subtract(const Duration(minutes: 12)).toUtc(),
                  createdAt: now.toUtc(),
                ),
              );
            }
          }
          final ec = EventController(
            repository: repo,
            now: () => now,
            newId: () => 'unused',
          );
          await ec.load();

          final pc = _PlanningFixture(repo, now)
            ..worldNodes = [
              WorldNode(
                id: 'node',
                name: '探索退火参数',
                status: WorldNodeStatus.inProgress,
                isFocused: true,
                sortOrder: 0,
                createdAt: now,
                updatedAt: now,
              ),
            ]
            ..plans = [
              Plan(
                id: 'plan',
                worldNodeId: 'node',
                status: PlanStatus.current,
                roundNumber: 1,
                createdAt: now,
                updatedAt: now,
              ),
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
                        textTheme: base.textTheme.apply(fontFamily: 'PhaseCQA'),
                      ),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Scaffold(
                  body: scene.startsWith('routine')
                      ? RoutinePage(
                          controller: ec,
                          collapseStore: InMemoryRoutineCategoryCollapseStore(),
                        )
                      : EventsPage(controller: ec, planningController: pc),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.byType(Card), findsNothing);
          Future<void> show(Finder target) async {
            if (target.evaluate().isEmpty) {
              await tester.scrollUntilVisible(
                target,
                250,
                scrollable: find.byType(Scrollable).first,
              );
            }
            await tester.ensureVisible(target);
            await tester.pumpAndSettle();
          }

          final prefix = '$scene-${platform.name}-${width.toInt()}-$scale';
          await capture(tester, boundary, prefix);
          if (scene.startsWith('today')) {
            if (scene != 'today-night') {
              await show(find.byKey(const ValueKey('today-now')));
              final warning = tester.widget<Text>(
                find.text('已超过理想时间 · 最晚 14:00'),
              );
              expect(warning.style!.color, HomePilot.warning);
            }
            expect(find.text('未开始'), findsNothing);
            expect(find.text('已完成的日常'), findsNothing);
            for (final key in [
              'today-paused-ex-rp',
              'today-waiting-ex-rw',
              'plan-step',
            ]) {
              await show(find.byKey(ValueKey(key)));
              expect(
                find.descendant(
                  of: find.byKey(ValueKey(key)),
                  matching: find.byType(ExecutionRowShell),
                ),
                findsOneWidget,
              );
            }
            expect(find.text('探索退火参数'), findsOneWidget);
            await capture(tester, boundary, '$prefix-persistent');
            if (scene != 'today-night') {
              await show(find.byKey(const ValueKey('today-later')));
              expect(find.text('17:30'), findsOneWidget);
              await capture(tester, boundary, '$prefix-later');
            }
          } else {
            await show(find.byKey(const ValueKey('routine-night')));
            expect(find.textContaining('次日 00:30'), findsOneWidget);
            await capture(tester, boundary, '$prefix-night');
            await tester.tap(find.byKey(const ValueKey('routine-more-night')));
            await tester.pumpAndSettle();
            await tester.tap(find.text('编辑'));
            await tester.pumpAndSettle();
            expect(find.text('基本信息'), findsOneWidget);
            expect(find.text('重复规则'), findsOneWidget);
            await tester.ensureVisible(
              find.byKey(const ValueKey('routine-time-start')),
            );
            await tester.pumpAndSettle();
            expect(find.text('次日 00:30'), findsOneWidget);
            expect(find.text('次日 02:00'), findsOneWidget);
            await capture(tester, boundary, '$prefix-time-edit');
            await tester.ensureVisible(find.byType(TextField).first);
            await tester.pumpAndSettle();
            await tester.enterText(
              find.byType(TextField).first,
              '很长的编辑名称，保存前仍可查看和取消',
            );
            if (platform == TargetPlatform.android) {
              tester.view.viewInsets = const FakeViewPadding(bottom: 300);
            }
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await capture(tester, boundary, '$prefix-keyboard');
            tester.view.resetViewInsets();
            await tester.pumpAndSettle();
            await tester.tap(find.text('取消'));
            await tester.pumpAndSettle();
            await show(find.byKey(const ValueKey('routine-more-demand')));
            await tester.tap(find.byKey(const ValueKey('routine-more-demand')));
            await tester.pumpAndSettle();
            await tester.tap(find.text('编辑'));
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('routine-time-recommendation-toggle')),
              findsNothing,
            );
            expect(
              find.byKey(const ValueKey('routine-home-quick-action-toggle')),
              findsNothing,
            );
            await tester.tap(find.text('保存'));
            await tester.pumpAndSettle();
            expect(
              repo.routines
                  .singleWhere((r) => r.id == 'demand')
                  .showInHomeQuickActions,
              isTrue,
            );
          }
          if (platform == TargetPlatform.windows) {
            final row = find.byType(ExecutionRowShell).first;
            await show(row);
            final before = tester.getRect(row);
            final mouse = await tester.createGesture(
              kind: PointerDeviceKind.mouse,
            );
            await mouse.addPointer(location: Offset.zero);
            await mouse.moveTo(before.center);
            await tester.pumpAndSettle();
            expect(tester.getRect(row), before);
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.pumpAndSettle();
            await mouse.removePointer();
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          ec.dispose();
          pc.dispose();
        });
      }
    }
  }
}

Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
  final dir = Platform.environment['JAX_C_DIR'];
  if (dir == null) return;
  await tester.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject() as RenderRepaintBoundary)
            .toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(dir).create(recursive: true);
    await File('$dir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
