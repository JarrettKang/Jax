import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/app.dart';
import 'package:jax/core/entities/event_day_plan.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/routine.dart';

import '../support/memory_repository.dart';
import '../support/ui_navigation.dart';

void main() {
  final now = DateTime(2026, 8, 27, 12);
  JaxEvent event(
    String id,
    EventStatus status, {
    String? parent,
    int order = 0,
  }) => JaxEvent(
    id: id,
    name: id,
    status: status,
    parentEventId: parent,
    sortOrder: order,
    createdAt: now,
    updatedAt: now,
  );

  testWidgets(
    'navigation and Today show only planned Events plus matching Routines',
    (tester) async {
      final repo =
          MemoryRepository([
              event('root', EventStatus.paused),
              event('计划事项', EventStatus.waiting, parent: 'root'),
              event('未来事项', EventStatus.pending, order: 1),
            ], false)
            ..eventDayPlans.add(
              EventDayPlan(
                eventId: '计划事项',
                dayKey: '2026-08-27',
                order: 0,
                createdAt: now,
              ),
            )
            ..routines.add(
              Routine(
                id: 'routine',
                name: '每日洗漱',
                recurrence: RoutineRecurrence.daily,
                weekdayMask: 0,
                isActive: true,
                sortOrder: 0,
                createdAt: now,
                updatedAt: now,
              ),
            );
      await tester.pumpWidget(JaxApp(repository: repo, now: () => now));
      await tester.pumpAndSettle();
      expect(find.text('今日'), findsOneWidget);
      expect(find.text('事件'), findsNothing);
      await tester.tap(find.text('今日'));
      await tester.pumpAndSettle();
      expect(find.text('今日事项'), findsOneWidget);
      expect(find.text('今日日常'), findsOneWidget);
      expect(find.text('计划事项'), findsOneWidget);
      expect(find.text('未来事项'), findsNothing);
      expect(find.text('root'), findsOneWidget);
      expect(find.text('等待中'), findsOneWidget);
      expect(find.text('每日洗漱'), findsOneWidget);
    },
  );

  testWidgets(
    'World adds and Today removes a paused Event without changing facts',
    (tester) async {
      final repo = MemoryRepository([event('A', EventStatus.paused)], false);
      await tester.pumpWidget(JaxApp(repository: repo, now: () => now));
      await tester.pumpAndSettle();
      await openEventsPage(tester);
      await tester.tap(find.byKey(const ValueKey('world-more-A')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('world-add-today-A')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('今日'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('today-event-A')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('today-remove-A')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('today-event-A')), findsNothing);
      expect(repo.events.single.status, EventStatus.paused);
      expect(repo.events.single.parentEventId, isNull);
      expect(repo.segments, isEmpty);
    },
  );

  testWidgets(
    'completed planned Event stays today but disappears next Jax day',
    (tester) async {
      var clock = now;
      final repo =
          MemoryRepository([event('done', EventStatus.completed)], false)
            ..eventDayPlans.add(
              EventDayPlan(
                eventId: 'done',
                dayKey: '2026-08-27',
                order: 0,
                createdAt: now,
              ),
            );
      await tester.pumpWidget(JaxApp(repository: repo, now: () => clock));
      await tester.pumpAndSettle();
      await tester.tap(find.text('今日'));
      await tester.pumpAndSettle();
      expect(find.text('done'), findsOneWidget);
      expect(find.text('已完成'), findsOneWidget);
      clock = DateTime(2026, 8, 27, 23, 1);
      await tester.tap(find.text('世界'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('今日'));
      await tester.pumpAndSettle();
      expect(find.text('done'), findsNothing);
    },
  );

  testWidgets('starting in World automatically plans the Event for Today', (
    tester,
  ) async {
    final repo = MemoryRepository([
      event('start-me', EventStatus.pending),
    ], false);
    await tester.pumpWidget(
      JaxApp(repository: repo, now: () => now, newId: () => 'segment'),
    );
    await tester.pumpAndSettle();
    await openEventsPage(tester);
    await tester.tap(find.byKey(const ValueKey('world-more-start-me')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('start-start-me')));
    await tester.pumpAndSettle();
    expect(repo.events.single.status, EventStatus.running);
    expect(repo.eventDayPlans.single.dayKey, '2026-08-27');
    await tester.tap(find.text('今日'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('today-event-start-me')), findsOneWidget);
  });

  testWidgets('23:00 uses next weekday and keeps one cross-day Routine', (
    tester,
  ) async {
    final late = DateTime(2026, 8, 27, 23, 10);
    final repo = MemoryRepository(const [], false)
      ..routines.addAll([
        Routine(
          id: 'fri',
          name: '星期五日常',
          recurrence: RoutineRecurrence.selectedWeekdays,
          weekdayMask: 1 << (DateTime.friday - 1),
          isActive: true,
          sortOrder: 0,
          createdAt: now,
          updatedAt: now,
        ),
        Routine(
          id: 'thu',
          name: '星期四日常',
          recurrence: RoutineRecurrence.selectedWeekdays,
          weekdayMask: 1 << (DateTime.thursday - 1),
          isActive: true,
          sortOrder: 1,
          createdAt: now,
          updatedAt: now,
        ),
        Routine(
          id: 'running',
          name: '跨日执行',
          recurrence: RoutineRecurrence.daily,
          weekdayMask: 0,
          isActive: true,
          sortOrder: 2,
          createdAt: now,
          updatedAt: now,
        ),
      ])
      ..routineExecutions.add(
        RoutineExecution(
          id: 'old-execution',
          routineId: 'running',
          occurrenceDate: '2026-08-27',
          status: RoutineExecutionStatus.running,
          createdAt: now,
          updatedAt: now,
        ),
      );
    await tester.pumpWidget(JaxApp(repository: repo, now: () => late));
    await tester.pumpAndSettle();
    await tester.tap(find.text('今日'));
    await tester.pumpAndSettle();
    expect(find.text('星期五日常'), findsOneWidget);
    expect(find.text('星期四日常'), findsNothing);
    expect(find.text('跨日执行'), findsNWidgets(2));
    expect(repo.routineExecutions, hasLength(1));
  });

  testWidgets(
    'Today Routine execution actions use text buttons through every state',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = MemoryRepository(const [], false)
        ..routines.add(
          Routine(
            id: 'focus',
            name: '一个用于验证小屏操作区不会溢出的长名称日常',
            recurrence: RoutineRecurrence.daily,
            weekdayMask: 0,
            isActive: true,
            sortOrder: 0,
            createdAt: now,
            updatedAt: now,
          ),
        );
      await tester.pumpWidget(
        JaxApp(repository: repo, now: () => now, newId: () => 'id'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('今日'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('today-routine-start-focus')),
        findsOneWidget,
      );
      expect(find.widgetWithText(OutlinedButton, '开始'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('today-routine-start-focus')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('today-routine-pause-focus')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('today-routine-complete-focus')),
        findsOneWidget,
      );
      expect(find.widgetWithText(OutlinedButton, '暂停'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '完成'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('today-routine-pause-focus')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('today-routine-resume-focus')),
        findsOneWidget,
      );
      expect(find.widgetWithText(OutlinedButton, '恢复'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '完成'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('today-routine-complete-focus')),
      );
      await tester.pumpAndSettle();

      expect(find.text('已完成'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('today-routine-start-focus')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('today-routine-resume-focus')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('today-routine-pause-focus')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('today-routine-complete-focus')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
