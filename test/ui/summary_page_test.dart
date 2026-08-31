import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/app.dart';
import 'package:jax/core/entities/category.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/event_day_plan.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/run_segment.dart';
import 'package:jax/core/entities/routine.dart';

import '../support/memory_repository.dart';

void main() {
  testWidgets('daily and weekly summaries remain readable on a narrow screen', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 700);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final now = DateTime(2026, 8, 27, 12);
    final repo =
        MemoryRepository([
            JaxEvent(
              id: 'root',
              name: '一个很长的开发项目根事件',
              status: EventStatus.paused,
              categoryId: 'dev',
              createdAt: now,
              updatedAt: now,
            ),
          ])
          ..categories.add(
            Category(
              id: 'dev',
              name: '一个很长的开发项目分类名称',
              sortOrder: 0,
              createdAt: now,
              updatedAt: now,
            ),
          )
          ..segments.add(
            RunSegment(
              id: 's',
              eventId: 'root',
              startedAt: DateTime(2026, 8, 27, 8),
              endedAt: DateTime(2026, 8, 27, 9),
              createdAt: now,
            ),
          );
    await tester.pumpWidget(JaxApp(repository: repo, now: () => now));
    await tester.pumpAndSettle();
    await tester.tap(find.text('记录'));
    await tester.pumpAndSettle();
    expect(find.text('今天 · 进行中'), findsOneWidget);
    expect(find.text('一个很长的开发项目分类名称'), findsOneWidget);
    expect(find.textContaining('1h 00m · 100%'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('今日时间分布'), findsOneWidget);
    expect(find.byKey(const ValueKey('timeline-visual-s-9-0')), findsOneWidget);
    await tester.scrollUntilVisible(find.text('执行记录'), 500);
    expect(find.text('执行记录'), findsOneWidget);
    expect(find.text('08:00 → 09:00'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('周总结'), -500);
    await tester.tap(find.text('周总结'));
    await tester.pumpAndSettle();
    expect(find.text('每日时间分配'), findsOneWidget);
    expect(find.text('周一'), findsOneWidget);
    expect(find.text('周日'), findsOneWidget);
    expect(find.byType(Scrollable), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('日总结'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(find.text('今日时间分布'), findsOneWidget);
    for (var switchIndex = 0; switchIndex < 3; switchIndex++) {
      await tester.tap(find.text('周总结'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('日总结'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
    await tester.pumpAndSettle();
    expect(find.text('今天 · 进行中'), findsOneWidget);
    expect(find.text('今日时间分布'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('执行记录'), 500);
    expect(find.text('执行记录'), findsOneWidget);
  });

  testWidgets('add execution record shows only grouped eligible candidates', (
    tester,
  ) async {
    final now = DateTime(2026, 8, 31, 12);
    JaxEvent event(String id, EventStatus status) => JaxEvent(
      id: id,
      name: 'Event $id',
      status: status,
      createdAt: now,
      updatedAt: now,
      firstStartedAt: status == EventStatus.pending ? null : now,
      completedAt: status == EventStatus.completed ? now : null,
    );
    Routine routine(
      String id, {
      RoutineType type = RoutineType.scheduled,
      bool active = true,
      RoutineRecurrence recurrence = RoutineRecurrence.daily,
    }) => Routine(
      id: id,
      name: 'Routine $id',
      type: type,
      recurrence: recurrence,
      weekdayMask: 0,
      isActive: active,
      sortOrder: 0,
      createdAt: now,
      updatedAt: now,
    );
    final repo =
        MemoryRepository([
            event('pending', EventStatus.pending),
            event('paused', EventStatus.paused),
            event('waiting', EventStatus.waiting),
            event('running-event', EventStatus.running),
            event('completed', EventStatus.completed),
            event('not-today-pending', EventStatus.pending),
            event('not-today-paused', EventStatus.paused),
          ], false)
          ..eventDayPlans.addAll([
            for (var index = 0; index < 5; index++)
              EventDayPlan(
                eventId: [
                  'pending',
                  'paused',
                  'waiting',
                  'running-event',
                  'completed',
                ][index],
                dayKey: '2026-08-31',
                order: index,
                createdAt: now,
              ),
          ])
          ..segments.add(
            RunSegment(
              id: 'event-open',
              eventId: 'running-event',
              startedAt: now,
              createdAt: now,
            ),
          )
          ..routines.addAll([
            routine('scheduled-unstarted'),
            routine('scheduled-paused'),
            routine('scheduled-running'),
            routine('scheduled-completed'),
            routine(
              'scheduled-not-today',
              recurrence: RoutineRecurrence.weekends,
            ),
            routine('quick', type: RoutineType.onDemand),
            routine('not-shortcut', type: RoutineType.onDemand, active: false),
            routine('quick-running', type: RoutineType.onDemand),
            routine('quick-paused', type: RoutineType.onDemand),
          ])
          ..routineExecutions.addAll([
            for (final pair in [
              ('scheduled-paused', RoutineExecutionStatus.paused),
              ('scheduled-running', RoutineExecutionStatus.running),
              ('scheduled-completed', RoutineExecutionStatus.completed),
              ('quick-running', RoutineExecutionStatus.running),
              ('quick-paused', RoutineExecutionStatus.paused),
            ])
              RoutineExecution(
                id: 'execution-${pair.$1}',
                routineId: pair.$1,
                occurrenceDate: '2026-08-31',
                status: pair.$2,
                createdAt: now,
                updatedAt: now,
              ),
          ]);
    await tester.pumpWidget(JaxApp(repository: repo, now: () => now));
    await tester.pumpAndSettle();
    await tester.tap(find.text('记录'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('添加执行记录'), 500);
    await tester.tap(find.text('添加执行记录'));
    await tester.pumpAndSettle();

    expect(find.text('今日事项'), findsOneWidget);
    expect(find.text('今日日常'), findsOneWidget);
    expect(find.text('快捷动作'), findsOneWidget);
    for (final id in [
      'pending',
      'paused',
      'waiting',
      'scheduled-unstarted',
      'scheduled-paused',
    ]) {
      expect(find.byKey(ValueKey('segment-candidate-$id')), findsOneWidget);
    }
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('segment-candidate-quick')),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(
      find.byKey(const ValueKey('segment-candidate-quick')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('segment-candidate-quick-paused')),
      findsOneWidget,
    );
    for (final id in [
      'running-event',
      'completed',
      'not-today-pending',
      'not-today-paused',
      'scheduled-running',
      'scheduled-completed',
      'scheduled-not-today',
      'not-shortcut',
      'quick-running',
    ]) {
      expect(find.byKey(ValueKey('segment-candidate-$id')), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'available gap tap prefills the manual record range on narrow UI',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 700);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });
      final now = DateTime(2026, 8, 31, 17, 30);
      final event = JaxEvent(
        id: 'planned',
        name: '检查超算',
        status: EventStatus.paused,
        createdAt: now,
        updatedAt: now,
        firstStartedAt: now.subtract(const Duration(hours: 2)),
      );
      final repo = MemoryRepository([event], false)
        ..eventDayPlans.add(
          EventDayPlan(
            eventId: event.id,
            dayKey: '2026-08-31',
            order: 0,
            createdAt: now,
          ),
        )
        ..segments.add(
          RunSegment(
            id: 'occupied',
            eventId: event.id,
            startedAt: DateTime(2026, 8, 31, 14),
            endedAt: DateTime(2026, 8, 31, 15, 10),
            createdAt: now,
          ),
        );
      await tester.pumpWidget(JaxApp(repository: repo, now: () => now));
      await tester.pumpAndSettle();
      await tester.tap(find.text('记录'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('添加执行记录'), 500);
      await tester.tap(find.text('添加执行记录'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('segment-candidate-planned')));
      await tester.pumpAndSettle();

      expect(find.text('可用空白时间'), findsOneWidget);
      final gap = find.byKey(const ValueKey('available-gap-1'));
      expect(gap, findsOneWidget);
      await tester.tap(gap);
      await tester.pumpAndSettle();
      expect(find.text('15:10'), findsWidgets);
      expect(find.text('17:30'), findsWidgets);
      expect(find.text('位于可用空白 15:10–17:30 内'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
