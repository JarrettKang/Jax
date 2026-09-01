import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/run_segment.dart';
import 'package:jax/core/entities/routine.dart';
import 'package:jax/ui/controllers/event_controller.dart';
import 'package:jax/ui/pages/home_page.dart';

import '../support/memory_repository.dart';

void main() {
  testWidgets('Event correction is a compact More action and refreshes timer', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final now = DateTime.utc(2026, 9, 1, 11);
    final original = DateTime.utc(2026, 9, 1, 10, 20);
    final repository =
        MemoryRepository([
            JaxEvent(
              id: 'event',
              name: '开发',
              status: EventStatus.running,
              firstStartedAt: original,
              createdAt: original,
              updatedAt: original,
            ),
          ])
          ..segments.add(
            RunSegment(
              id: 'open',
              eventId: 'event',
              startedAt: original,
              createdAt: original,
            ),
          );
    final controller = EventController(
      repository: repository,
      newId: () => 'unused',
      now: () => now,
    );
    await controller.load();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        home: Scaffold(
          body: HomePage(
            controller: controller,
            now: () => now,
            onOpenEvents: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('00:40:00'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('home-running-more')));
    await tester.pumpAndSettle();
    expect(find.text('修改开始时间…'), findsOneWidget);
    await tester.tap(find.text('修改开始时间…'));
    await tester.pumpAndSettle();
    expect(find.text('修改开始时间'), findsOneWidget);
    expect(find.textContaining('当前记录开始于'), findsOneWidget);
    expect(find.byKey(const ValueKey('running-start-date')), findsOneWidget);
    expect(find.byKey(const ValueKey('running-start-time')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    final error = await controller.adjustRunningEventStart(
      'event',
      original,
      DateTime.utc(2026, 9, 1, 10),
    );
    await tester.pump();
    expect(error, isNull);
    expect(find.text('01:00:00'), findsOneWidget);
    expect(repository.segments, hasLength(1));
    expect(repository.segments.single.id, 'open');
    expect(repository.segments.single.endedAt, isNull);
    controller.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('stale dialog rejects after the Event was completed', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 9, 1, 11);
    final original = DateTime.utc(2026, 9, 1, 10, 20);
    final event = JaxEvent(
      id: 'event',
      name: '开发',
      status: EventStatus.running,
      firstStartedAt: original,
      createdAt: original,
      updatedAt: original,
    );
    final repository = MemoryRepository([event])
      ..segments.add(
        RunSegment(
          id: 'open',
          eventId: event.id,
          startedAt: original,
          createdAt: original,
        ),
      );
    final controller = EventController(
      repository: repository,
      newId: () => 'unused',
      now: () => now,
    );
    await controller.load();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomePage(
            controller: controller,
            now: () => now,
            onOpenEvents: () {},
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('home-running-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('修改开始时间…'));
    await tester.pumpAndSettle();

    repository.events[0] = event.copyWith(
      status: EventStatus.completed,
      completedAt: now,
      updatedAt: now,
    );
    repository.segments[0] = repository.segments[0].copyWith(endedAt: now);
    await tester.tap(find.byKey(const ValueKey('save-running-start')));
    await tester.pumpAndSettle();

    expect(find.textContaining('当前执行状态已发生变化'), findsOneWidget);
    expect(repository.segments.single.startedAt, original);
    expect(repository.segments.single.endedAt, now);
    controller.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Routine running Hero exposes the same correction dialog', (
    tester,
  ) async {
    await _setPhoneViewport(tester);
    final now = DateTime.utc(2026, 9, 1, 11);
    final original = DateTime.utc(2026, 9, 1, 10, 20);
    final repository = MemoryRepository()
      ..routines.add(
        Routine(
          id: 'routine',
          name: '拉伸',
          type: RoutineType.onDemand,
          recurrence: RoutineRecurrence.daily,
          weekdayMask: 0,
          isActive: true,
          sortOrder: 0,
          createdAt: original,
          updatedAt: original,
        ),
      )
      ..routineExecutions.add(
        RoutineExecution(
          id: 'execution',
          routineId: 'routine',
          occurrenceDate: '2026-09-01',
          status: RoutineExecutionStatus.running,
          createdAt: original,
          updatedAt: original,
        ),
      )
      ..routineSegments.add(
        RoutineRunSegment(
          id: 'routine-open',
          executionId: 'execution',
          startedAt: original,
          createdAt: original,
        ),
      );
    final controller = EventController(
      repository: repository,
      newId: () => 'unused',
      now: () => now,
    );
    await controller.load();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomePage(
            controller: controller,
            now: () => now,
            onOpenEvents: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('home-running-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('修改开始时间…'));
    await tester.pumpAndSettle();
    expect(find.text('修改开始时间'), findsOneWidget);
    expect(find.byKey(const ValueKey('save-running-start')), findsOneWidget);
    expect(tester.takeException(), isNull);
    controller.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<void> _setPhoneViewport(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(320, 700);
  tester.platformDispatcher.textScaleFactorTestValue = 1.3;
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}

Future<void> _setDesktopViewport(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1280, 900);
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
}
