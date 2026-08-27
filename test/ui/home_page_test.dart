import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/app.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/run_segment.dart';

import '../support/memory_repository.dart';

void main() {
  testWidgets('shows greeting and opens events when nothing is running', (
    tester,
  ) async {
    final now = DateTime(2026, 8, 25, 9);
    await tester.pumpWidget(
      JaxApp(repository: MemoryRepository(), now: () => now),
    );
    await tester.pumpAndSettle();

    expect(find.text('上午好，我是 Jax'), findsOneWidget);
    expect(find.text('我们来做点什么？'), findsOneWidget);

    await tester.tap(find.text('我们来做点什么？'));
    await tester.pumpAndSettle();
    expect(find.text('今日事项'), findsOneWidget);
    expect(find.text('今天还没有安排事项'), findsOneWidget);
  });

  testWidgets('shows running context and ordered waiting summary', (
    tester,
  ) async {
    final now = DateTime(2026, 8, 26, 12);
    final repository =
        MemoryRepository([
            _event('root', 'Root', EventStatus.paused, now, sortOrder: 0),
            _event('run', 'Running', EventStatus.running, now, sortOrder: 1),
            _event(
              'w1',
              'Waiting one',
              EventStatus.waiting,
              now,
              parent: 'root',
              sortOrder: 0,
            ),
            _event('w2', 'Waiting two', EventStatus.waiting, now, sortOrder: 2),
          ])
          ..segments.add(
            RunSegment(
              id: 'run-segment',
              eventId: 'run',
              startedAt: now,
              createdAt: now,
            ),
          );
    await tester.pumpWidget(JaxApp(repository: repository, now: () => now));
    await tester.pumpAndSettle();
    expect(find.text('当前正在做'), findsOneWidget);
    expect(find.text('同时在等待'), findsOneWidget);
    expect(find.text('Waiting one'), findsOneWidget);
    expect(find.text('Root'), findsWidgets);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('home-waiting-w1'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('home-waiting-w2'))).dy,
      ),
    );
  });

  testWidgets('shows waiting even without a running event', (tester) async {
    final now = DateTime(2026, 8, 26, 12);
    await tester.pumpWidget(
      JaxApp(
        repository: MemoryRepository([
          _event('w', 'Waiting', EventStatus.waiting, now),
        ]),
        now: () => now,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('当前没有正在执行的事项'), findsOneWidget);
    expect(find.text('同时在等待'), findsOneWidget);
    expect(find.text('我们来做点什么？'), findsNothing);
  });

  testWidgets('shows work subject, ancestor and ordered step states', (
    tester,
  ) async {
    var now = DateTime(2026, 8, 25, 12);
    final repository =
        MemoryRepository([
            _event('a', 'A', EventStatus.paused, now),
            _event('b', 'B', EventStatus.paused, now, parent: 'a'),
            _event(
              'c',
              'C',
              EventStatus.completed,
              now,
              parent: 'b',
              sortOrder: 0,
            ),
            _event(
              'd',
              'D',
              EventStatus.running,
              now,
              parent: 'b',
              sortOrder: 1,
            ),
            _event(
              'e',
              'E',
              EventStatus.pending,
              now,
              parent: 'b',
              sortOrder: 2,
            ),
          ])
          ..segments.add(
            RunSegment(
              id: 'd-run',
              eventId: 'd',
              startedAt: now,
              createdAt: now,
            ),
          );

    await tester.pumpWidget(JaxApp(repository: repository, now: () => now));
    await tester.pumpAndSettle();

    expect(find.text('当前正在做'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-work-subject')), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-ancestor-path')), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
    expect(_stepY(tester, 'c'), lessThan(_stepY(tester, 'd')));
    expect(_stepY(tester, 'd'), lessThan(_stepY(tester, 'e')));
    expect(find.byKey(const ValueKey('home-step-completed-c')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-step-running-d')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-step-pending-e')), findsOneWidget);
    expect(find.text('进行中 · 00:00:00'), findsOneWidget);
    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('进行中 · 00:00:01'), findsOneWidget);
  });

  testWidgets('refreshes the greeting after crossing a time boundary', (
    tester,
  ) async {
    var now = DateTime(2026, 8, 25, 8, 59, 59);
    await tester.pumpWidget(
      JaxApp(repository: MemoryRepository(), now: () => now),
    );
    await tester.pumpAndSettle();
    expect(find.text('早上好，我是 Jax'), findsOneWidget);

    now = DateTime(2026, 8, 25, 9);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('上午好，我是 Jax'), findsOneWidget);
  });

  testWidgets('supports an arbitrary-depth ancestor path', (tester) async {
    final now = DateTime(2026, 8, 25, 12);
    final repository = MemoryRepository([
      _event('a', 'A', EventStatus.paused, now),
      _event('b', 'B', EventStatus.paused, now, parent: 'a'),
      _event('c', 'C', EventStatus.paused, now, parent: 'b'),
      _event('d', 'D', EventStatus.paused, now, parent: 'c'),
      _event('e', 'E', EventStatus.running, now, parent: 'd'),
      _event('f', 'F', EventStatus.pending, now, parent: 'd'),
    ]);

    await tester.pumpWidget(JaxApp(repository: repository, now: () => now));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(const ValueKey('home-work-subject'))).data,
      'D',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('home-ancestor-path')))
          .data,
      'A › B › C',
    );
    expect(find.byKey(const ValueKey('home-step-e')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-step-f')), findsOneWidget);
  });

  testWidgets('top-level running Event is its own subject and step', (
    tester,
  ) async {
    final now = DateTime(2026, 8, 25, 12);
    final repository = MemoryRepository([
      _event('a', 'A', EventStatus.running, now),
      _event('b', 'B', EventStatus.pending, now),
    ]);
    await tester.pumpWidget(JaxApp(repository: repository, now: () => now));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(const ValueKey('home-work-subject'))).data,
      'A',
    );
    expect(find.byKey(const ValueKey('home-ancestor-path')), findsNothing);
    expect(find.byKey(const ValueKey('home-step-a')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-step-b')), findsNothing);
  });

  testWidgets('keeps non-standard statuses in explicit sibling order', (
    tester,
  ) async {
    final now = DateTime(2026, 8, 25, 12);
    final repository = MemoryRepository([
      _event('parent', 'Parent', EventStatus.paused, now),
      _event(
        'a',
        'A',
        EventStatus.pending,
        now,
        parent: 'parent',
        sortOrder: 0,
      ),
      _event(
        'b',
        'B',
        EventStatus.completed,
        now,
        parent: 'parent',
        sortOrder: 1,
      ),
      _event(
        'c',
        'C',
        EventStatus.running,
        now,
        parent: 'parent',
        sortOrder: 2,
      ),
      _event('d', 'D', EventStatus.paused, now, parent: 'parent', sortOrder: 3),
      _event(
        'e',
        'E',
        EventStatus.pending,
        now,
        parent: 'parent',
        sortOrder: 4,
      ),
    ]);
    await tester.pumpWidget(JaxApp(repository: repository, now: () => now));
    await tester.pumpAndSettle();

    final positions = [
      'a',
      'b',
      'c',
      'd',
      'e',
    ].map((id) => _stepY(tester, id)).toList();
    expect(positions, orderedEquals([...positions]..sort()));
    expect(find.byKey(const ValueKey('home-step-pending-a')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-step-completed-b')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-step-running-c')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-step-paused-d')), findsOneWidget);
  });

  testWidgets('shows the running step when it is the only child', (
    tester,
  ) async {
    final now = DateTime(2026, 8, 25, 12);
    final repository = MemoryRepository([
      _event('parent', '论文项目', EventStatus.paused, now),
      _event('running', '修改正文', EventStatus.running, now, parent: 'parent'),
    ]);

    await tester.pumpWidget(JaxApp(repository: repository, now: () => now));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(const ValueKey('home-work-subject'))).data,
      '论文项目',
    );
    expect(find.byKey(const ValueKey('home-step-running')), findsOneWidget);
  });

  testWidgets('many siblings use a local window and never hide running', (
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
    final now = DateTime(2026, 8, 25, 12);
    final events = <JaxEvent>[
      _event('parent', '很长的工作主体名称用于验证手机布局', EventStatus.paused, now),
      for (var index = 0; index < 12; index++)
        _event(
          'step-$index',
          '很长的步骤名称 $index',
          index == 6 ? EventStatus.running : EventStatus.pending,
          now,
          parent: 'parent',
          sortOrder: index,
        ),
    ];
    await tester.pumpWidget(
      JaxApp(repository: MemoryRepository(events), now: () => now),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('home-step-step-6')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-step-step-0')), findsNothing);
    expect(find.byKey(const ValueKey('home-omitted-before')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-omitted-after')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tracks start pause resume and complete state changes', (
    tester,
  ) async {
    var now = DateTime(2026, 8, 25, 12);
    var nextId = 0;
    final repository = MemoryRepository([
      _event('task', '状态同步任务', EventStatus.pending, now),
    ]);
    await tester.pumpWidget(
      JaxApp(
        repository: repository,
        now: () => now,
        newId: () => 'segment-${nextId++}',
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('我们来做点什么？'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('start-task')));
    await tester.pump();
    await tester.tap(find.text('首页'));
    await tester.pump();
    expect(find.text('状态同步任务'), findsWidgets);

    await tester.tap(find.text('今日'));
    await tester.pump();
    now = now.add(const Duration(minutes: 1));
    await tester.tap(find.byKey(const ValueKey('pause-task')));
    await tester.pump();
    await tester.tap(find.text('首页'));
    await tester.pump();
    expect(find.text('我们来做点什么？'), findsOneWidget);

    await tester.tap(find.text('今日'));
    await tester.pump();
    now = now.add(const Duration(minutes: 1));
    await tester.tap(find.byKey(const ValueKey('resume-task')));
    await tester.pump();
    await tester.tap(find.text('首页'));
    await tester.pump();
    expect(find.text('状态同步任务'), findsWidgets);

    await tester.tap(find.text('今日'));
    await tester.pump();
    now = now.add(const Duration(minutes: 1));
    await tester.tap(find.byKey(const ValueKey('complete-task')));
    await tester.pump();
    await tester.tap(find.text('首页'));
    await tester.pump();
    expect(find.text('我们来做点什么？'), findsOneWidget);
  });
}

double _stepY(WidgetTester tester, String id) =>
    tester.getTopLeft(find.byKey(ValueKey('home-step-$id'))).dy;

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
