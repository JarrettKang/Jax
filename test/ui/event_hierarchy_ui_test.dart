import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/app.dart';
import 'package:jax/core/entities/category.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';

import '../support/memory_repository.dart';
import '../support/ui_navigation.dart';

void main() {
  final time = DateTime.utc(2026, 8, 25, 8);
  JaxEvent event(
    String id,
    String name, {
    String? parent,
    String? categoryId,
    int? order,
  }) => JaxEvent(
    id: id,
    name: name,
    status: EventStatus.pending,
    parentEventId: parent,
    categoryId: categoryId,
    sortOrder: order,
    createdAt: time,
    updatedAt: time,
  );

  testWidgets('browses direct hierarchy and moves then detaches an Event', (
    tester,
  ) async {
    final repository = MemoryRepository([
      event('root', '项目甲'),
      event('child', '任务甲一', parent: 'root'),
      event('other', '项目乙'),
    ]);
    await tester.pumpWidget(JaxApp(repository: repository, now: () => time));
    await tester.pumpAndSettle();
    await openEventsPage(tester);

    await openEventMenu(tester, 'child');
    await tester.tap(find.byKey(const ValueKey('hierarchy-child')));
    await tester.pumpAndSettle();
    expect(find.text('上层事件'), findsOneWidget);
    expect(find.text('项目甲'), findsWidgets);

    await tester.tap(find.text('设置上层'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('hierarchy-candidate-child')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<ListTile>(
            find.byKey(const ValueKey('hierarchy-candidate-child')),
          )
          .enabled,
      isFalse,
    );
    await tester.tap(find.byKey(const ValueKey('hierarchy-candidate-other')));
    await tester.pumpAndSettle();
    expect(find.text('确认移动'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '移动'));
    await tester.pumpAndSettle();
    expect((await repository.getParent('child'))?.id, 'other');

    await tester.tap(find.text('解除上层'));
    await tester.pumpAndSettle();
    expect(await repository.getParent('child'), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'picker keeps category tree order and marks illegal current relations',
    (tester) async {
      final repository =
          MemoryRepository([
              event('A', 'A', categoryId: 'dev', order: 0),
              event('B', 'B', parent: 'A', order: 0),
              event('C', 'C', parent: 'B', order: 0),
              event('peer', '同分类候选', categoryId: 'dev', order: 1),
              event('D', 'D', categoryId: 'research', order: 0),
              event('E', 'E', parent: 'D', order: 0),
            ])
            ..categories.addAll([
              Category(
                id: 'dev',
                name: '开发项目',
                sortOrder: 0,
                createdAt: time,
                updatedAt: time,
              ),
              Category(
                id: 'research',
                name: '科研',
                sortOrder: 1,
                createdAt: time,
                updatedAt: time,
              ),
            ]);
      await tester.pumpWidget(JaxApp(repository: repository, now: () => time));
      await tester.pumpAndSettle();
      await tester.tap(find.text('世界'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('world-category-open-dev')));
      await tester.pumpAndSettle();
      await openEventMenu(tester, 'B');
      await tester.tap(find.byKey(const ValueKey('hierarchy-B')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('设置上层'));
      await tester.pumpAndSettle();
      for (final id in ['A', 'B', 'C', 'peer']) {
        expect(find.byKey(ValueKey('hierarchy-candidate-$id')), findsOneWidget);
      }
      for (final id in ['D', 'E']) {
        expect(find.byKey(ValueKey('hierarchy-candidate-$id')), findsNothing);
      }
      expect(find.byKey(const ValueKey('hierarchy-no-parent')), findsOneWidget);
      expect(find.text('当前上层'), findsOneWidget);
      expect(find.text('当前事件'), findsOneWidget);
      expect(find.text('下层，不能作为上层'), findsOneWidget);
      expect(
        tester
            .widget<ListTile>(
              find.byKey(const ValueKey('hierarchy-candidate-C')),
            )
            .enabled,
        isFalse,
      );
      final positions = [
        for (final id in ['A', 'B', 'C', 'peer'])
          tester.getTopLeft(find.byKey(ValueKey('hierarchy-candidate-$id'))).dy,
      ];
      expect(positions, orderedEquals([...positions]..sort()));

      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加下层'));
      await tester.pumpAndSettle();
      expect(find.text('当前下层'), findsOneWidget);
      expect(find.text('上层，不能作为下层'), findsOneWidget);
      expect(
        tester
            .widget<ListTile>(
              find.byKey(const ValueKey('hierarchy-candidate-A')),
            )
            .enabled,
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('hierarchy detail remains usable on narrow large-text phone', (
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
      event('root', '这是一个很长的上层事件名称'),
      event('child', '这是一个很长的下层事件名称', parent: 'root'),
    ]);
    await tester.pumpWidget(JaxApp(repository: repository, now: () => time));
    await tester.pumpAndSettle();
    await openEventsPage(tester);
    await openEventMenu(tester, 'root');
    await tester.tap(find.byKey(const ValueKey('hierarchy-root')));
    await tester.pumpAndSettle();

    expect(find.text('直接下层'), findsOneWidget);
    expect(find.text('添加下层'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsWidgets);
    await tester.tap(find.text('设置上层'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('hierarchy-candidate-root')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('hierarchy-candidate-child')),
      findsOneWidget,
    );
    expect(find.byType(ListView), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
