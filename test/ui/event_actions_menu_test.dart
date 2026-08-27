import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/app.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/run_segment.dart';

import '../support/memory_repository.dart';
import '../support/ui_navigation.dart';

void main() {
  final time = DateTime.utc(2026, 8, 26, 8);

  JaxEvent event(String id, EventStatus status, {String? parent, int? order}) =>
      JaxEvent(
        id: id,
        name: '$id 的超长事件名称用于验证响应式操作区布局',
        status: status,
        parentEventId: parent,
        sortOrder: order,
        firstStartedAt: status == EventStatus.pending ? null : time,
        createdAt: time,
        updatedAt: time,
      );

  testWidgets('Today cards expose only execution and plan actions', (
    tester,
  ) async {
    final repository =
        MemoryRepository([
            event('pending', EventStatus.pending, order: 0),
            event('paused', EventStatus.paused, order: 1),
            event('running', EventStatus.running, order: 2),
            event('waiting', EventStatus.waiting, order: 3),
          ])
          ..segments.add(
            RunSegment(
              id: 'running-segment',
              eventId: 'running',
              startedAt: time,
              createdAt: time,
            ),
          );
    await tester.pumpWidget(JaxApp(repository: repository, now: () => time));
    await tester.pumpAndSettle();
    await tester.tap(find.text('今日'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('start-pending')), findsOneWidget);
    expect(find.byKey(const ValueKey('resume-paused')), findsOneWidget);
    expect(find.byKey(const ValueKey('pause-running')), findsOneWidget);
    expect(find.byKey(const ValueKey('complete-running')), findsOneWidget);
    expect(find.text('等待中'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '恢复'), findsNWidgets(2));
    expect(find.widgetWithText(FilledButton, '完成'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('pause-waiting')), findsNothing);
    expect(find.byKey(const ValueKey('today-remove-pending')), findsOneWidget);
    expect(find.byKey(const ValueKey('today-remove-running')), findsNothing);
  });

  testWidgets('parent menu hides deletion and menu actions remain usable', (
    tester,
  ) async {
    final repository = MemoryRepository([
      event('parent', EventStatus.pending, order: 0),
      event('child', EventStatus.pending, parent: 'parent', order: 0),
      event('sibling', EventStatus.pending, order: 1),
    ]);
    await tester.pumpWidget(JaxApp(repository: repository, now: () => time));
    await tester.pumpAndSettle();
    await openEventsPage(tester);

    await tester.tap(find.byKey(const ValueKey('world-more-parent')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('delete-parent')), findsNothing);
    expect(find.byKey(const ValueKey('hierarchy-parent')), findsOneWidget);
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('world-more-sibling')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('edit-sibling')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AlertDialog, '编辑事件'), findsOneWidget);
  });

  testWidgets('running actions and menu do not overflow on a narrow phone', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 700);
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final repository = MemoryRepository([event('running', EventStatus.running)])
      ..segments.add(
        RunSegment(
          id: 'segment',
          eventId: 'running',
          startedAt: time,
          createdAt: time,
        ),
      );
    await tester.pumpWidget(JaxApp(repository: repository, now: () => time));
    await tester.pumpAndSettle();
    await tester.tap(find.text('今日'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, '暂停'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '完成'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('waiting text actions do not overflow on a narrow phone', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 700);
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final repository = MemoryRepository([
      event('waiting', EventStatus.waiting),
    ]);
    await tester.pumpWidget(JaxApp(repository: repository, now: () => time));
    await tester.pumpAndSettle();
    await tester.tap(find.text('今日'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, '恢复'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '完成'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
