import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/app.dart';
import 'package:jax/core/entities/category.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';

import '../support/memory_repository.dart';
import '../support/ui_navigation.dart';

void main() {
  testWidgets('creates an event without exposing its id', (tester) async {
    final repository = MemoryRepository();
    await tester.pumpWidget(
      JaxApp(
        repository: repository,
        newId: () => 'hidden-id',
        now: () => DateTime.utc(2026, 8, 24, 12),
      ),
    );
    await tester.pumpAndSettle();
    await openEventsPage(tester);
    await tester.tap(find.text('新建事件'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '学习 Flutter');
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();
    expect(find.text('学习 Flutter'), findsOneWidget);
    expect(find.text('hidden-id'), findsNothing);
    expect(repository.events, hasLength(1));
  });
  testWidgets('shows validation and does not create an empty event', (
    tester,
  ) async {
    final repository = MemoryRepository();
    await tester.pumpWidget(JaxApp(repository: repository));
    await tester.pumpAndSettle();
    await openEventsPage(tester);
    await tester.tap(find.text('新建事件'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();
    expect(find.text('事件名称不能为空'), findsOneWidget);
    expect(repository.events, isEmpty);
  });

  testWidgets('creates a root Event directly in the selected Category', (
    tester,
  ) async {
    final repository = MemoryRepository()
      ..categories.add(
        Category(
          id: 'research',
          name: '科研',
          sortOrder: 0,
          createdAt: DateTime.utc(2026, 8, 24),
          updatedAt: DateTime.utc(2026, 8, 24),
        ),
      );
    await tester.pumpWidget(
      JaxApp(repository: repository, newId: () => 'root-id'),
    );
    await tester.pumpAndSettle();
    await openEventsPage(tester);
    await tester.tap(find.byKey(const ValueKey('world-new-event')));
    await tester.pumpAndSettle();

    expect(find.text('分类'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '测试 Yukawa');
    await tester.tap(find.byKey(const ValueKey('world-create-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('科研').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();

    expect(repository.events.single.categoryId, 'research');
    expect(find.text('科研'), findsOneWidget);
    expect(find.text('测试 Yukawa'), findsOneWidget);
  });

  testWidgets(
    'child creation shows inherited Category and stores no direct one',
    (tester) async {
      final parent = JaxEvent(
        id: 'parent',
        name: '测试 Yukawa',
        status: EventStatus.pending,
        createdAt: DateTime.utc(2026, 8, 24),
        updatedAt: DateTime.utc(2026, 8, 24),
        categoryId: 'research',
      );
      final repository = MemoryRepository([parent])
        ..categories.add(
          Category(
            id: 'research',
            name: '科研',
            sortOrder: 0,
            createdAt: DateTime.utc(2026, 8, 24),
            updatedAt: DateTime.utc(2026, 8, 24),
          ),
        );
      await tester.pumpWidget(
        JaxApp(repository: repository, newId: () => 'child-id'),
      );
      await tester.pumpAndSettle();
      await openEventsPage(tester);
      await tester.tap(find.byKey(const ValueKey('world-new-event')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('world-create-category')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('科研').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('world-create-parent')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('测试 Yukawa').last);
      await tester.pumpAndSettle();

      expect(find.text('由上层事件继承'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('world-create-category')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('world-create-parent')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('无（顶级事件）').last);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('category-value-research')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('world-create-parent')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('测试 Yukawa').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '测试截断距离');
      await tester.tap(find.text('创建'));
      await tester.pumpAndSettle();

      final child = repository.events.singleWhere(
        (event) => event.id == 'child-id',
      );
      expect(child.parentEventId, parent.id);
      expect(child.categoryId, isNull);
      expect(find.text('测试截断距离'), findsOneWidget);
    },
  );

  testWidgets('long Category names stay usable in the narrow create form', (
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
    const longName = '这是一个用于验证小屏分类选择器布局的很长分类名称';
    final repository = MemoryRepository()
      ..categories.add(
        Category(
          id: 'long',
          name: longName,
          sortOrder: 0,
          createdAt: DateTime.utc(2026, 8, 24),
          updatedAt: DateTime.utc(2026, 8, 24),
        ),
      );
    await tester.pumpWidget(JaxApp(repository: repository));
    await tester.pumpAndSettle();
    await openEventsPage(tester);
    await tester.tap(find.byKey(const ValueKey('world-new-event')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('world-create-category')));
    await tester.pumpAndSettle();

    expect(find.text(longName), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
