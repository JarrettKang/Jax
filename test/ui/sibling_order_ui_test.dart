import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/app.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';

import '../support/memory_repository.dart';
import '../support/ui_navigation.dart';

void main() {
  final time = DateTime.utc(2026, 8, 25, 8);
  JaxEvent event(String id, int order, {String? parent}) => JaxEvent(
    id: id,
    name: id,
    status: EventStatus.pending,
    parentEventId: parent,
    sortOrder: order,
    createdAt: time,
    updatedAt: time,
  );

  testWidgets('events page displays and changes sibling order', (tester) async {
    final repository = MemoryRepository([
      event('a', 0),
      event('b', 1),
      event('c', 2),
    ]);
    await tester.pumpWidget(JaxApp(repository: repository, now: () => time));
    await tester.pumpAndSettle();
    await openEventsPage(tester);

    double y(String id) => tester.getTopLeft(find.text(id)).dy;
    expect(y('a'), lessThan(y('b')));
    expect(y('b'), lessThan(y('c')));
    await tester.tap(find.byKey(const ValueKey('move-down-a')));
    await tester.pumpAndSettle();
    expect(y('b'), lessThan(y('a')));
    expect(y('a'), lessThan(y('c')));
    expect((await repository.getOrderedTopLevelEvents()).map((e) => e.id), [
      'b',
      'a',
      'c',
    ]);
  });

  testWidgets('ordering controls remain usable on narrow large-text phone', (
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
      event('long-a', 0),
      event('long-b', 1),
    ]);
    await tester.pumpWidget(JaxApp(repository: repository, now: () => time));
    await tester.pumpAndSettle();
    await openEventsPage(tester);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('move-down-long-a')),
      100,
    );
    expect(find.byKey(const ValueKey('move-up-long-b')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
