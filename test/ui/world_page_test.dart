import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:jax/app.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/category.dart';

import '../support/memory_repository.dart';

void main() {
  final now = DateTime(2026, 8, 26, 12);
  JaxEvent event(
    String id,
    EventStatus status, {
    String? parent,
    String? categoryId,
    int? order,
  }) => JaxEvent(
    id: id,
    name: id,
    status: status,
    parentEventId: parent,
    categoryId: categoryId,
    sortOrder: order,
    createdAt: now,
    updatedAt: now,
  );

  testWidgets('world shows all statuses in hierarchy order', (tester) async {
    final repository = MemoryRepository([
      event('A', EventStatus.pending, order: 0),
      event('B', EventStatus.completed, parent: 'A', order: 0),
      event('C', EventStatus.paused, parent: 'A', order: 1),
      event('D', EventStatus.waiting, parent: 'A', order: 2),
      event('E', EventStatus.running, parent: 'A', order: 3),
    ]);
    await tester.pumpWidget(JaxApp(repository: repository, now: () => now));
    await tester.pumpAndSettle();
    await tester.tap(find.text('世界'));
    await tester.pumpAndSettle();
    for (final id in ['A', 'B', 'C', 'D', 'E']) {
      expect(find.byKey(ValueKey('world-node-$id')), findsOneWidget);
      final tooltip = tester.widget<Tooltip>(
        find.descendant(
          of: find.byKey(ValueKey('world-more-$id')),
          matching: find.byType(Tooltip),
        ),
      );
      expect(tooltip.message, '更多操作');
    }
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('world-node-B'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('world-node-C'))).dy,
      ),
    );
    expect(find.text('已完成'), findsOneWidget);
    expect(find.text('等待中'), findsOneWidget);
    expect(find.text('推进中'), findsOneWidget);
    expect(
      (tester.getCenter(find.text('E')).dy -
              tester.getCenter(find.text('正在执行')).dy)
          .abs(),
      lessThan(4),
      reason: 'wide World rows keep the Event title and status inline',
    );
  });

  testWidgets('world collapse hides descendants and restores them', (
    tester,
  ) async {
    final repository = MemoryRepository([
      event('A', EventStatus.pending, order: 0),
      event('B', EventStatus.paused, parent: 'A', order: 0),
      event('C', EventStatus.completed, parent: 'B', order: 0),
    ]);
    await tester.pumpWidget(JaxApp(repository: repository, now: () => now));
    await tester.pumpAndSettle();
    await tester.tap(find.text('世界'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('world-toggle-A')));
    await tester.pump();
    expect(find.byKey(const ValueKey('world-node-B')), findsNothing);
    expect(find.byKey(const ValueKey('world-node-C')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('world-toggle-A')));
    await tester.pump();
    expect(find.byKey(const ValueKey('world-node-C')), findsOneWidget);
  });

  testWidgets('narrow World lays out long deep Event names without overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const rootName = '这是一个很长的上层事件名称用于验证世界页小屏布局';
    const childName = '这是一个很长的深层事件名称用于验证状态和操作不会溢出';
    final repository = MemoryRepository([
      event(rootName, EventStatus.pending, order: 0),
      event(childName, EventStatus.running, parent: rootName, order: 0),
    ]);

    await tester.pumpWidget(JaxApp(repository: repository, now: () => now));
    await tester.pumpAndSettle();
    await tester.tap(find.text('世界'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(rootName), findsOneWidget);
    expect(find.text(childName), findsOneWidget);
    expect(find.text('正在执行'), findsOneWidget);
  });

  testWidgets('old unclassified roots stay unclassified after first category', (
    tester,
  ) async {
    final repository = MemoryRepository([
      event('old-A', EventStatus.pending, order: 0),
      event('old-B', EventStatus.paused, order: 1),
    ]);
    await tester.pumpWidget(JaxApp(repository: repository, now: () => now));
    await tester.pumpAndSettle();
    await tester.tap(find.text('世界'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('world-new-category')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '科研工作');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(repository.categories.single.name, '科研工作');
    expect(find.text('科研工作'), findsOneWidget);
    expect(find.text('未分类'), findsOneWidget);
    expect(find.byKey(const ValueKey('world-node-old-A')), findsOneWidget);
    expect(find.byKey(const ValueKey('world-node-old-B')), findsOneWidget);
  });

  testWidgets('empty World shows its first created category', (tester) async {
    final repository = MemoryRepository();
    await tester.pumpWidget(JaxApp(repository: repository, now: () => now));
    await tester.pumpAndSettle();
    await tester.tap(find.text('世界'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('world-new-category')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '开发项目');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('开发项目'), findsOneWidget);
  });

  testWidgets('World safely shows categorized and unclassified roots', (
    tester,
  ) async {
    final repository =
        MemoryRepository([
            event('A', EventStatus.pending, categoryId: 'dev', order: 0),
            event('B', EventStatus.pending, order: 1),
          ])
          ..categories.add(
            Category(
              id: 'dev',
              name: '开发项目',
              sortOrder: 0,
              createdAt: now,
              updatedAt: now,
            ),
          );
    await tester.pumpWidget(JaxApp(repository: repository, now: () => now));
    await tester.pumpAndSettle();
    await tester.tap(find.text('世界'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('开发项目'), findsOneWidget);
    expect(find.text('未分类'), findsOneWidget);
    expect(find.byKey(const ValueKey('world-node-A')), findsOneWidget);
    expect(find.byKey(const ValueKey('world-node-B')), findsOneWidget);
  });

  testWidgets('deleting a category returns its root to 未分类 safely', (
    tester,
  ) async {
    final repository =
        MemoryRepository([
            event('A', EventStatus.pending, categoryId: 'dev', order: 0),
          ])
          ..categories.add(
            Category(
              id: 'dev',
              name: '开发项目',
              sortOrder: 0,
              createdAt: now,
              updatedAt: now,
            ),
          );
    await tester.pumpWidget(JaxApp(repository: repository, now: () => now));
    await tester.pumpAndSettle();
    await tester.tap(find.text('世界'));
    await tester.pumpAndSettle();
    final categoryTooltip = tester.widget<Tooltip>(
      find.descendant(
        of: find.byKey(const ValueKey('world-category-more-dev')),
        matching: find.byType(Tooltip),
      ),
    );
    expect(categoryTooltip.message, '分类操作');
    await tester.tap(find.byKey(const ValueKey('world-category-more-dev')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除分类'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('未分类'), findsOneWidget);
    expect(find.byKey(const ValueKey('world-node-A')), findsOneWidget);
  });
}
