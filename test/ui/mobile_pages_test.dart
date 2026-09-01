import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/app.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/run_segment.dart';

import '../support/memory_repository.dart';

void main() {
  testWidgets('all event actions remain usable on a narrow phone', (
    tester,
  ) async {
    await _setPhoneViewport(tester);
    final time = DateTime.utc(2026, 8, 25, 8);
    final repository =
        MemoryRepository([
            _event(
              'pending',
              '这是一个很长的未开始事件名称用于验证手机布局',
              EventStatus.pending,
              time,
            ),
            _event('paused', '这是一个很长的暂停事件名称用于验证手机布局', EventStatus.paused, time),
            _event(
              'running',
              '这是一个很长的运行事件名称用于验证手机布局',
              EventStatus.running,
              time,
            ),
          ])
          ..segments.addAll([
            RunSegment(
              id: 'paused-segment',
              eventId: 'paused',
              startedAt: time,
              endedAt: time.add(const Duration(minutes: 1)),
              createdAt: time,
            ),
            RunSegment(
              id: 'running-segment',
              eventId: 'running',
              startedAt: time,
              createdAt: time,
            ),
          ]);

    await tester.pumpWidget(JaxApp(repository: repository, now: () => time));
    await tester.pumpAndSettle();
    await tester.tap(find.text('今日'));
    await tester.pumpAndSettle();

    final pendingName = find.text('这是一个很长的未开始事件名称用于验证手机布局');
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('start-pending'))).dy,
      greaterThan(tester.getTopLeft(pendingName).dy),
    );

    for (final key in [
      'start-pending',
      'resume-paused',
      'complete-running',
      'pause-running',
    ]) {
      final action = find.byKey(ValueKey(key));
      await tester.scrollUntilVisible(action, 100);
      expect(action, findsOneWidget);
    }
    final newEvent = find.byKey(const ValueKey('add-standalone-event'));
    await tester.tap(newEvent);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);

    expect(tester.takeException(), isNull);
  });

  testWidgets('long history content scrolls without overflow on a phone', (
    tester,
  ) async {
    await _setPhoneViewport(tester);
    final time = DateTime.utc(2026, 8, 25, 8);
    final completed = _event(
      'completed',
      '这是一个很长的已完成事件名称用于验证手机历史记录布局',
      EventStatus.completed,
      time,
    ).copyWith(completedAt: time.add(const Duration(hours: 2)));
    final repository = MemoryRepository([completed])
      ..segments.add(
        RunSegment(
          id: 'completed-segment',
          eventId: completed.id,
          startedAt: time,
          endedAt: time.add(const Duration(hours: 2)),
          createdAt: time,
        ),
      );

    await tester.pumpWidget(JaxApp(repository: repository, now: () => time));
    await tester.pumpAndSettle();
    await tester.tap(find.text('记录'));
    await tester.pumpAndSettle();

    expect(find.text('日总结'), findsOneWidget);
    expect(find.text('周总结'), findsOneWidget);
    expect(find.byType(Scrollable), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

JaxEvent _event(String id, String name, EventStatus status, DateTime time) =>
    JaxEvent(
      id: id,
      name: name,
      status: status,
      firstStartedAt: status == EventStatus.pending ? null : time,
      createdAt: time,
      updatedAt: time,
    );

Future<void> _setPhoneViewport(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(320, 700);
  tester.platformDispatcher.textScaleFactorTestValue = 1.5;
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}
