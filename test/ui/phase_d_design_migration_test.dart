import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/app.dart' show buildJaxTheme;
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/run_segment.dart';
import 'package:jax/core/preferences/app_preferences.dart';
import 'package:jax/ui/controllers/event_controller.dart';
import 'package:jax/ui/controllers/app_preferences_controller.dart';
import 'package:jax/ui/pages/summary_page.dart';
import 'package:jax/ui/pages/settings_page.dart';
import 'package:jax/ui/theme/desktop_polish.dart';

import '../support/memory_repository.dart';

void main() {
  testWidgets('Windows settings Tab Enter Escape and three dialog widths', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final prefs = AppPreferencesController(InMemoryAppPreferencesStore());
    await prefs.load();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildJaxTheme(TargetPlatform.windows),
        home: SettingsPage(controller: prefs),
      ),
    );
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('assistant-name-setting'));
    final rowContext = tester.element(row);
    for (final entry in [
      (DesktopDialogSize.confirmation, 400.0),
      (DesktopDialogSize.form, 560.0),
      (DesktopDialogSize.complex, 720.0),
    ]) {
      expect(DesktopPolish.dialog(rowContext, entry.$1)!.maxWidth, entry.$2);
    }
    final originalRect = tester.getRect(row);
    var focused = false;
    for (var i = 0; i < 12; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      final focusContext = FocusManager.instance.primaryFocus?.context;
      if (focusContext != null &&
          (focusContext == rowContext ||
              focusContext.findAncestorWidgetOfExactType<SettingsPage>() !=
                  null)) {
        final ink = find.descendant(of: row, matching: find.byType(InkWell));
        if (ink.evaluate().isNotEmpty &&
            Focus.of(tester.element(ink.first)).hasFocus) {
          focused = true;
          break;
        }
      }
    }
    expect(focused, isTrue);
    expect(tester.getRect(row), originalRect);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      tester
          .widget<AlertDialog>(find.byType(AlertDialog))
          .constraints!
          .maxWidth,
      560,
    );
    await tester.enterText(
      find.byKey(const ValueKey('assistant-name-input')),
      '键盘保存',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(prefs.value.assistantName, '键盘保存');
    expect(find.byType(AlertDialog), findsNothing);
    await tester.tap(row);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('assistant-name-input')),
      '取消编辑',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(prefs.value.assistantName, '键盘保存');
    await tester.pumpWidget(const SizedBox());
    prefs.dispose();
  });
  for (final (platform, width) in [
    (TargetPlatform.android, 320.0),
    (TargetPlatform.android, 390.0),
    (TargetPlatform.windows, 480.0),
    (TargetPlatform.windows, 1400.0),
  ]) {
    for (final scale in [1.0, 2.0]) {
      for (final scene in ['empty', 'single', 'segments', 'settings']) {
        testWidgets('Phase D $scene ${platform.name} $width $scale', (
          tester,
        ) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 1000);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final font = Platform.environment['JAX_D_FONT'];
          await tester.runAsync(() async {
            for (final (family, path) in [
              ('PhaseDQA', font),
              ('MaterialIcons', Platform.environment['JAX_D_ICONS']),
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
          final repo = MemoryRepository(
            scene == 'empty'
                ? []
                : [
                    JaxEvent(
                      id: 'work',
                      name: '分析实验参数与记录结果：完整保留很长的执行事项名称',
                      status: EventStatus.running,
                      createdAt: now,
                      updatedAt: now,
                    ),
                  ],
          );
          if (scene != 'empty') {
            final spans = scene == 'single'
                ? [(DateTime(2026, 9, 17, 10), DateTime(2026, 9, 17, 10, 30))]
                : [
                    (
                      DateTime(2026, 9, 16, 23, 30),
                      DateTime(2026, 9, 17, 0, 30),
                    ),
                    (DateTime(2026, 9, 17, 10), DateTime(2026, 9, 17, 10, 30)),
                    (DateTime(2026, 9, 17, 11), DateTime(2026, 9, 17, 11, 20)),
                    (DateTime(2026, 9, 17, 11, 40), null),
                  ];
            for (var i = 0; i < spans.length; i++) {
              repo.segments.add(
                RunSegment(
                  id: 's$i',
                  eventId: 'work',
                  startedAt: spans[i].$1,
                  endedAt: spans[i].$2,
                  createdAt: now,
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
          final store = InMemoryAppPreferencesStore();
          final preferences = AppPreferencesController(store);
          await preferences.load();
          final boundary = GlobalKey();
          final base = buildJaxTheme(platform);
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                scrollBehavior: const JaxScrollBehavior(),
                theme: font == null
                    ? base
                    : base.copyWith(
                        textTheme: base.textTheme.apply(fontFamily: 'PhaseDQA'),
                      ),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: scene == 'settings'
                    ? SettingsPage(controller: preferences)
                    : Scaffold(body: SummaryPage(controller: ec)),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final prefix = '$scene-${platform.name}-${width.toInt()}-$scale';
          Future<void> shot(String suffix) async {
            final dir = Platform.environment['JAX_D_DIR'];
            if (dir == null) return;
            await tester.runAsync(() async {
              await Directory(dir).create(recursive: true);
              final image =
                  await (boundary.currentContext!.findRenderObject()
                          as RenderRepaintBoundary)
                      .toImage();
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File('$dir/$prefix-$suffix.png')
                  .writeAsBytes(data!.buffer.asUint8List());
              image.dispose();
            });
          }

          Future<void> show(Finder target) async {
            if (target.evaluate().isEmpty) {
              await tester.scrollUntilVisible(
                target,
                250,
                scrollable: find.byType(Scrollable).first,
              );
            }
            await Scrollable.ensureVisible(
              tester.element(target),
              alignment: 0.5,
            );
            await tester.pumpAndSettle();
          }

          await shot('initial');
          if (scene == 'settings') {
            expect(find.text(defaultAssistantName), findsOneWidget);
            await tester.tap(
              find.byKey(const ValueKey('assistant-name-setting')),
            );
            await tester.pumpAndSettle();
            final input = find.byKey(const ValueKey('assistant-name-input'));
            await tester.enterText(input, '');
            await tester.pumpAndSettle();
            expect(find.text('名称不能为空'), findsOneWidget);
            await shot('error');
            await tester.enterText(input, '很长的管家名称用于验证完整显示与保存');
            await tester.pumpAndSettle();
            await tester.tap(find.byKey(const ValueKey('save-assistant-name')));
            await tester.pumpAndSettle();
            expect((await store.load()).assistantName, '很长的管家名称用于验证完整显示与保存');
            await shot('custom');
            await tester.tap(
              find.byKey(const ValueKey('assistant-name-setting')),
            );
            await tester.pumpAndSettle();
            await tester.enterText(input, '不保存的名字');
            await tester.tap(
              find.byKey(const ValueKey('cancel-assistant-name')),
            );
            await tester.pumpAndSettle();
            expect((await store.load()).assistantName, '很长的管家名称用于验证完整显示与保存');
          } else {
            if (scene != 'empty') {
              await show(find.byKey(const ValueKey('record-segment-s0')));
              expect(
                find.text(
                  scene == 'single'
                      ? '10:00 → 10:30'
                      : '2026-09-16 23:30 → 2026-09-17 00:30',
                ),
                findsOneWidget,
              );
              expect(
                tester
                    .getSize(find.byKey(const ValueKey('record-segment-s0')))
                    .height,
                greaterThanOrEqualTo(48),
              );
              if (platform == TargetPlatform.windows) {
                final row = find.byKey(const ValueKey('record-segment-s0'));
                final rect = tester.getRect(row);
                final mouse = await tester.createGesture(
                  kind: PointerDeviceKind.mouse,
                );
                await mouse.addPointer(location: Offset.zero);
                await mouse.moveTo(rect.center);
                await tester.pumpAndSettle();
                expect(tester.getRect(row), rect);
                await mouse.removePointer();
              }
              await tester.tap(
                find
                    .ancestor(
                      of: find.byKey(const ValueKey('record-segment-s0')),
                      matching: find.byType(InkWell),
                    )
                    .first,
              );
              await tester.pumpAndSettle();
              await shot('edit');
              expect(find.text('保存'), findsOneWidget);
              if (platform == TargetPlatform.windows) {
                await tester.sendKeyEvent(LogicalKeyboardKey.escape);
              } else {
                await tester.binding.handlePopRoute();
              }
              await tester.pumpAndSettle();
              if (scene == 'segments') {
                await show(find.byKey(const ValueKey('record-segment-s3')));
                await tester.tap(
                  find
                      .ancestor(
                        of: find.byKey(const ValueKey('record-segment-s3')),
                        matching: find.byType(InkWell),
                      )
                      .first,
                );
                await tester.pumpAndSettle();
                expect(find.text('正在执行 · 请在 Today 中暂停或完成'), findsOneWidget);
                await shot('open');
                await tester.binding.handlePopRoute();
                await tester.pumpAndSettle();
              }
            }
            await show(find.text('今日时间分布'));
            await shot('chart');
            tester
                .state<ScrollableState>(find.byType(Scrollable).first)
                .position
                .jumpTo(0);
            await tester.pumpAndSettle();
            await tester.tap(find.text('周总结'));
            await tester.pumpAndSettle();
            await shot('week');
          }
          if (platform == TargetPlatform.windows) {
            expect(
              tester
                  .widgetList<Scrollbar>(find.byType(Scrollbar))
                  .any((s) => s.thumbVisibility == true),
              isTrue,
            );
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.pumpAndSettle();
            tester.view.physicalSize = Size(width == 1400 ? 480 : 1400, 1000);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await shot('resize');
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          ec.dispose();
          preferences.dispose();
        });
      }
    }
  }
}
