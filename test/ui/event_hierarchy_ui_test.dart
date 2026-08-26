import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/app.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';

import '../support/memory_repository.dart';
import '../support/ui_navigation.dart';

void main() {
  final time = DateTime.utc(2026, 8, 25, 8);
  JaxEvent event(String id, String name, {String? parent}) => JaxEvent(
    id: id,
    name: name,
    status: EventStatus.pending,
    parentEventId: parent,
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
      findsNothing,
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
    expect(tester.takeException(), isNull);
  });
}
