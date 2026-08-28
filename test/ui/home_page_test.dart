import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/app.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/routine.dart';
import 'package:jax/core/entities/routine_category.dart';
import 'package:jax/core/entities/run_segment.dart';

import '../support/memory_repository.dart';

void main() {
  testWidgets('idle home offers deterministic Today candidates', (
    tester,
  ) async {
    final now = DateTime(2026, 8, 25, 9);
    final repository = MemoryRepository([
      _event('first', '处理数据', EventStatus.pending, now, sortOrder: 0),
      _event('second', '写论文', EventStatus.paused, now, sortOrder: 1),
    ]);
    await tester.pumpWidget(
      JaxApp(
        repository: repository,
        now: () => now,
        newId: () => 'new-segment',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('上午好'), findsOneWidget);
    expect(find.text('现在没有正在执行的事项'), findsOneWidget);
    expect(find.text('接下来可以做'), findsOneWidget);
    expect(_nextY(tester, 'first'), lessThan(_nextY(tester, 'second')));

    await tester.tap(find.byKey(const ValueKey('home-next-start-first')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-running-hero')), findsOneWidget);
    expect(find.text('处理数据'), findsOneWidget);
    expect(
      repository.events.firstWhere((e) => e.id == 'first').status,
      EventStatus.running,
    );
  });

  testWidgets(
    'running Event is hero with breadcrumb duration and direct actions',
    (tester) async {
      var now = DateTime(2026, 8, 25, 12);
      final repository =
          MemoryRepository([
              _event('root', '开发 Jax', EventStatus.paused, now),
              _event(
                'parent',
                '开发 v0.2',
                EventStatus.paused,
                now,
                parent: 'root',
              ),
              _event(
                'done',
                '添加首页',
                EventStatus.completed,
                now,
                parent: 'parent',
                sortOrder: 0,
              ),
              _event(
                'run',
                '优化界面和操作',
                EventStatus.running,
                now,
                parent: 'parent',
                sortOrder: 1,
              ),
              _event(
                'next',
                '写提示词',
                EventStatus.pending,
                now,
                parent: 'parent',
                sortOrder: 2,
              ),
            ])
            ..segments.add(
              RunSegment(
                id: 'open',
                eventId: 'run',
                startedAt: now,
                createdAt: now,
              ),
            );
      await tester.pumpWidget(JaxApp(repository: repository, now: () => now));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('home-running-name')))
            .data,
        '优化界面和操作',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('home-running-context')))
            .data,
        '开发 Jax › 开发 v0.2',
      );
      expect(find.text('开发 v0.2 · 1 / 3 已完成'), findsOneWidget);
      expect(find.text('00:00:00'), findsOneWidget);
      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('00:00:01'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('home-running-pause')));
      await tester.pumpAndSettle();
      expect(find.text('现在没有正在执行的事项'), findsOneWidget);
      expect(
        repository.events.firstWhere((e) => e.id == 'run').status,
        EventStatus.paused,
      );
    },
  );

  testWidgets('Event More exposes complete and waiting actions', (
    tester,
  ) async {
    final now = DateTime(2026, 8, 25, 12);
    final repository =
        MemoryRepository([_event('run', '运行任务', EventStatus.running, now)])
          ..segments.add(
            RunSegment(
              id: 'open',
              eventId: 'run',
              startedAt: now,
              createdAt: now,
            ),
          );
    await tester.pumpWidget(JaxApp(repository: repository, now: () => now));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-running-more')));
    await tester.pumpAndSettle();
    expect(find.text('完成'), findsOneWidget);
    expect(find.text('等待'), findsOneWidget);
    await tester.tap(find.text('等待'));
    await tester.pumpAndSettle();
    expect(repository.events.single.status, EventStatus.waiting);
    expect(find.text('等待中 · 1'), findsOneWidget);
  });

  testWidgets('running Routine shows category recurrence and can pause', (
    tester,
  ) async {
    final now = DateTime(2026, 8, 25, 12);
    final repository = MemoryRepository();
    repository.routineCategories.add(
      RoutineCategory(
        id: 'cat',
        name: '日常起居',
        sortOrder: 0,
        createdAt: now,
        updatedAt: now,
      ),
    );
    repository.routines.add(
      Routine(
        id: 'routine',
        name: '晚上洗漱',
        routineCategoryId: 'cat',
        recurrence: RoutineRecurrence.daily,
        weekdayMask: 0,
        isActive: true,
        sortOrder: 0,
        createdAt: now,
        updatedAt: now,
      ),
    );
    repository.routineExecutions.add(
      RoutineExecution(
        id: 'execution',
        routineId: 'routine',
        occurrenceDate: '2026-08-24',
        status: RoutineExecutionStatus.running,
        createdAt: now,
        updatedAt: now,
      ),
    );
    repository.routineSegments.add(
      RoutineRunSegment(
        id: 'segment',
        executionId: 'execution',
        startedAt: now,
        createdAt: now,
      ),
    );
    await tester.pumpWidget(JaxApp(repository: repository, now: () => now));
    await tester.pumpAndSettle();

    expect(find.text('晚上洗漱'), findsOneWidget);
    expect(find.text('日常起居 · 每日'), findsOneWidget);
    expect(find.text('00:00:00'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('home-running-pause')));
    await tester.pumpAndSettle();
    expect(
      repository.routineExecutions.single.status,
      RoutineExecutionStatus.paused,
    );
  });

  testWidgets('starting next item pauses current global running', (
    tester,
  ) async {
    final now = DateTime(2026, 8, 25, 12);
    var id = 0;
    final repository =
        MemoryRepository([
            _event('run', '当前任务', EventStatus.running, now, sortOrder: 0),
            _event('next', '下一任务', EventStatus.pending, now, sortOrder: 1),
          ])
          ..segments.add(
            RunSegment(
              id: 'open',
              eventId: 'run',
              startedAt: now,
              createdAt: now,
            ),
          );
    await tester.pumpWidget(
      JaxApp(
        repository: repository,
        now: () => now,
        newId: () => 'new-${id++}',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-next-start-next')));
    await tester.pumpAndSettle();
    expect(
      repository.events.firstWhere((e) => e.id == 'run').status,
      EventStatus.paused,
    );
    expect(
      repository.events.firstWhere((e) => e.id == 'next').status,
      EventStatus.running,
    );
    expect(find.text('下一任务'), findsOneWidget);
  });

  testWidgets('waiting is secondary and narrow layout does not overflow', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 700);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final now = DateTime(2026, 8, 25, 12);
    final repository =
        MemoryRepository([
            _event('run', '非常长的当前执行事项名称用于验证手机布局不会溢出', EventStatus.running, now),
            _event('wait', '等待外部结果', EventStatus.waiting, now, sortOrder: 1),
          ])
          ..segments.add(
            RunSegment(
              id: 'open',
              eventId: 'run',
              startedAt: now,
              createdAt: now,
            ),
          );
    await tester.pumpWidget(JaxApp(repository: repository, now: () => now));
    await tester.pumpAndSettle();
    expect(find.text('等待中 · 1'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-waiting-wait')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

double _nextY(WidgetTester tester, String id) =>
    tester.getTopLeft(find.byKey(ValueKey('home-next-$id'))).dy;

JaxEvent _event(
  String id,
  String name,
  EventStatus status,
  DateTime now, {
  String? parent,
  int? sortOrder,
}) => JaxEvent(
  id: id,
  name: name,
  status: status,
  parentEventId: parent,
  createdAt: now,
  updatedAt: now,
  firstStartedAt: status == EventStatus.pending ? null : now,
  completedAt: status == EventStatus.completed ? now : null,
  sortOrder: sortOrder,
);
