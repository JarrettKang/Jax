import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/app.dart' show buildJaxTheme;
import 'package:jax/core/entities/category.dart' as model;
import 'package:jax/core/entities/world_node.dart';
import 'package:jax/core/entities/routine.dart';
import 'package:jax/core/entities/plan.dart';
import 'package:jax/core/entities/plan_item.dart';
import 'package:jax/core/preferences/world_category_collapse_store.dart';
import 'package:jax/core/preferences/routine_category_collapse_store.dart';
import 'package:jax/ui/controllers/event_controller.dart';
import 'package:jax/ui/pages/events_page.dart';
import 'package:jax/ui/pages/routine_page.dart';
import 'package:jax/ui/pages/world_page.dart';
import 'package:jax/ui/widgets/execution_row_shell.dart';
import 'package:jax/ui/widgets/world_node_browsing_row.dart';

import '../support/memory_repository.dart';
import '../support/home_category_fixture.dart';

class _Plans extends HomeSnapshotController {
  _Plans(super.events, super.time);
  @override
  List<PlanItem> get projectedTodayItems => [
    for (var i = 0; i < 12; i++)
      PlanItem(
        id: 'p$i',
        planId: 'plan',
        title: i % 3 == 0 ? '校对实验记录与参数' : '处理实验事项 $i',
        status: PlanItemStatus.next,
        sortOrder: i,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
  ];
}

void main() {
  for (final (platform, width) in [
    (TargetPlatform.android, 360.0),
    (TargetPlatform.android, 390.0),
    (TargetPlatform.android, 430.0),
    (TargetPlatform.windows, 480.0),
    (TargetPlatform.windows, 1400.0),
  ]) {
    for (final scale in [1.0, 2.0]) {
      for (final page in ['today', 'routine', 'world']) {
        testWidgets('density $page ${platform.name} $width $scale', (
          tester,
        ) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 844);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final font = Platform.environment['DENSITY_FONT'];
          await tester.runAsync(() async {
            for (final (family, path) in [
              ('DensityQA', font),
              ('MaterialIcons', Platform.environment['DENSITY_ICONS']),
            ]) {
              if (path != null) {
                await ui.loadFontFromList(
                  File(path).readAsBytesSync(),
                  fontFamily: family,
                );
              }
            }
          });
          final now = DateTime(2026, 9, 17, 12);
          final repo = MemoryRepository();
          for (var i = 0; i < 12; i++) {
            repo.routines.add(
              Routine(
                id: 'r$i',
                name: i % 3 == 0
                    ? '午饭与餐后整理'
                    : i % 3 == 1
                    ? '起床洗漱'
                    : '按需整理思路',
                type: i % 3 == 2 ? RoutineType.onDemand : RoutineType.scheduled,
                recurrence: RoutineRecurrence.daily,
                weekdayMask: 0,
                isActive: true,
                sortOrder: i,
                createdAt: now,
                updatedAt: now,
                timeRecommendation: i % 3 == 0
                    ? const RoutineTimeRecommendation(
                        startMinute: 660,
                        endMinute: 780,
                        latestEndMinute: 1020,
                      )
                    : null,
              ),
            );
          }
          final ec = EventController(
            repository: repo,
            now: () => now,
            newId: () => 'unused',
          );
          await ec.load();
          final pc = _Plans(repo, now)
            ..plans = [
              Plan(
                id: 'plan',
                worldNodeId: 'root',
                status: PlanStatus.current,
                roundNumber: 1,
                createdAt: now,
                updatedAt: now,
              ),
            ]
            ..categories = [
              for (var c = 0; c < 3; c++)
                model.Category(
                  id: 'c$c',
                  name: '分类 $c',
                  sortOrder: c,
                  createdAt: now,
                  updatedAt: now,
                ),
            ]
            ..worldNodes = [
              WorldNode(
                id: 'root',
                name: '实验研究',
                status: WorldNodeStatus.inProgress,
                isFocused: true,
                sortOrder: 0,
                createdAt: now,
                updatedAt: now,
              ),
              for (var i = 0; i < 15; i++)
                WorldNode(
                  id: 'n$i',
                  name: i % 2 == 0 ? '研究材料与环境参数，保留完整的结构名称' : '实验节点 $i',
                  categoryId: 'c${i ~/ 5}',
                  status: i % 5 == 2
                      ? WorldNodeStatus.completed
                      : WorldNodeStatus.inProgress,
                  isFocused: i % 5 == 1,
                  sortOrder: i,
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
                        textTheme: base.textTheme.apply(
                          fontFamily: 'DensityQA',
                        ),
                      ),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Scaffold(
                  appBar: AppBar(title: Text(page)),
                  bottomNavigationBar: NavigationBar(
                    selectedIndex: 0,
                    destinations: const [
                      NavigationDestination(
                        icon: Icon(Icons.home),
                        label: '首页',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.today),
                        label: '今日',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.public),
                        label: '世界',
                      ),
                    ],
                  ),
                  body: switch (page) {
                    'today' => EventsPage(
                      controller: ec,
                      planningController: pc,
                    ),
                    'routine' => RoutinePage(
                      controller: ec,
                      collapseStore: InMemoryRoutineCategoryCollapseStore(),
                    ),
                    _ => WorldPage(
                      controller: pc,
                      worldCategoryCollapseStore:
                          InMemoryWorldCategoryCollapseStore(),
                    ),
                  },
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final rows = find.byType(
            page == 'world' ? WorldNodeBrowsingRow : ExecutionRowShell,
          );
          final viewport = tester.getRect(find.byType(Scrollable).first);
          final rects = [
            for (final e in rows.evaluate())
              tester.getRect(find.byWidget(e.widget)),
          ];
          final fullyVisible = rects
              .where(
                (r) => r.top >= viewport.top && r.bottom <= viewport.bottom,
              )
              .length;
          final firstHeight = rects.first.height;
          for (final rect in rects) {
            expect(rect.height, greaterThanOrEqualTo(48));
          }
          if (page == 'routine' && (width < 880 || scale > 1.25)) {
            final more = find.byKey(const ValueKey('routine-more-r0'));
            final first = find.byKey(const ValueKey('routine-r0'));
            expect(
              tester.getTopLeft(more).dy,
              closeTo(tester.getTopLeft(first).dy + 8, 0.1),
            );
          }

          final controls = find.byWidgetPredicate(
            (w) =>
                w is IconButton ||
                w is PopupMenuButton<String> ||
                w is OutlinedButton ||
                w is FilledButton,
          );
          for (final e in controls.evaluate()) {
            final size = tester.getSize(find.byWidget(e.widget));
            expect(size.width, greaterThanOrEqualTo(48));
            expect(size.height, greaterThanOrEqualTo(48));
          }
          final stage = Platform.environment['DENSITY_STAGE'];
          if (stage != null) {
            await tester.runAsync(() async {
              final dir = Directory('build/density-qa/$stage');
              await dir.create(recursive: true);
              final name = '$page-${platform.name}-${width.toInt()}-$scale';
              await File('${dir.path}/$name.json').writeAsString(
                jsonEncode({
                  'fullyVisible': fullyVisible,
                  'firstRowHeight': firstHeight,
                  'viewportHeight': viewport.height,
                }),
              );
              final image =
                  await (boundary.currentContext!.findRenderObject()
                          as RenderRepaintBoundary)
                      .toImage();
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File('${dir.path}/$name.png')
                  .writeAsBytes(data!.buffer.asUint8List());
              image.dispose();
            });
          }
          await tester.pumpWidget(const SizedBox());
          ec.dispose();
          pc.dispose();
        });
      }
    }
  }
}
