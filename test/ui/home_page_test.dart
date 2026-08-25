import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/app.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';

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
    expect(find.text('暂无未完成事件'), findsOneWidget);
  });

  testWidgets('shows only the running event', (tester) async {
    final now = DateTime(2026, 8, 25, 12);
    final repository = MemoryRepository([
      _event('pending', '待开始', EventStatus.pending, now),
      _event('paused', '已暂停', EventStatus.paused, now),
      _event('running', '修改论文', EventStatus.running, now),
      _event('completed', '已完成', EventStatus.completed, now),
    ]);

    await tester.pumpWidget(JaxApp(repository: repository, now: () => now));
    await tester.pumpAndSettle();

    expect(find.text('当前正在执行：'), findsOneWidget);
    expect(find.text('修改论文'), findsOneWidget);
    expect(find.text('待开始'), findsNothing);
    expect(find.text('已暂停'), findsNothing);
    expect(find.text('已完成'), findsNothing);
    expect(find.text('我们来做点什么？'), findsNothing);
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

  testWidgets('shows parent and siblings only with meaningful context', (
    tester,
  ) async {
    final now = DateTime(2026, 8, 25, 12);
    final repository = MemoryRepository([
      _event('parent', '论文项目', EventStatus.paused, now),
      _event('running', '修改正文', EventStatus.running, now, parent: 'parent'),
      _event('sibling', '整理参考文献', EventStatus.pending, now, parent: 'parent'),
    ]);

    await tester.pumpWidget(JaxApp(repository: repository, now: () => now));
    await tester.pumpAndSettle();

    expect(find.text('上层：论文项目'), findsOneWidget);
    expect(find.text('同级事件：整理参考文献'), findsOneWidget);
  });

  testWidgets('keeps F1 home when running Event has no other sibling', (
    tester,
  ) async {
    final now = DateTime(2026, 8, 25, 12);
    final repository = MemoryRepository([
      _event('parent', '论文项目', EventStatus.paused, now),
      _event('running', '修改正文', EventStatus.running, now, parent: 'parent'),
    ]);

    await tester.pumpWidget(JaxApp(repository: repository, now: () => now));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('home-running-parent')), findsNothing);
    expect(find.byKey(const ValueKey('home-running-siblings')), findsNothing);
    expect(find.text('修改正文'), findsOneWidget);
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
    expect(find.text('状态同步任务'), findsOneWidget);

    await tester.tap(find.text('事件'));
    await tester.pump();
    now = now.add(const Duration(minutes: 1));
    await tester.tap(find.byKey(const ValueKey('pause-task')));
    await tester.pump();
    await tester.tap(find.text('首页'));
    await tester.pump();
    expect(find.text('我们来做点什么？'), findsOneWidget);

    await tester.tap(find.text('事件'));
    await tester.pump();
    now = now.add(const Duration(minutes: 1));
    await tester.tap(find.byKey(const ValueKey('resume-task')));
    await tester.pump();
    await tester.tap(find.text('首页'));
    await tester.pump();
    expect(find.text('状态同步任务'), findsOneWidget);

    await tester.tap(find.text('事件'));
    await tester.pump();
    now = now.add(const Duration(minutes: 1));
    await tester.tap(find.byKey(const ValueKey('complete-task')));
    await tester.pump();
    await tester.tap(find.text('首页'));
    await tester.pump();
    expect(find.text('我们来做点什么？'), findsOneWidget);
  });
}

JaxEvent _event(
  String id,
  String name,
  EventStatus status,
  DateTime now, {
  String? parent,
}) => JaxEvent(
  id: id,
  name: name,
  status: status,
  parentEventId: parent,
  createdAt: now,
  updatedAt: now,
  firstStartedAt: status == EventStatus.pending ? null : now,
  completedAt: status == EventStatus.completed ? now : null,
);
