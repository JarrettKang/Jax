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
    await openEventMenu(tester, 'a');
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

  testWidgets(
    'hides boundary reorder controls and caps deep hierarchy indent',
    (tester) async {
      final repository = MemoryRepository([
        event('a', 0),
        event('b', 0, parent: 'a'),
        event('c', 0, parent: 'b'),
        event('e', 0, parent: 'c'),
        event('d', 1, parent: 'b'),
      ]);
      await tester.pumpWidget(JaxApp(repository: repository, now: () => time));
      await tester.pumpAndSettle();
      await openEventsPage(tester);

      Future<void> expectOrdering(
        String id, {
        required bool up,
        required bool down,
      }) async {
        await openEventMenu(tester, id);
        expect(
          find.byKey(ValueKey('move-up-$id')),
          up ? findsOneWidget : findsNothing,
        );
        expect(
          find.byKey(ValueKey('move-down-$id')),
          down ? findsOneWidget : findsNothing,
        );
        await tester.tapAt(Offset.zero);
        await tester.pumpAndSettle();
      }

      await expectOrdering('b', up: false, down: false);
      await expectOrdering('c', up: false, down: true);
      await expectOrdering('d', up: true, down: false);
      await expectOrdering('e', up: false, down: false);

      final aLeft = tester.getTopLeft(find.text('a')).dx;
      final bLeft = tester.getTopLeft(find.text('b')).dx;
      final cLeft = tester.getTopLeft(find.text('c')).dx;
      final eLeft = tester.getTopLeft(find.text('e')).dx;
      expect(bLeft, greaterThan(aLeft));
      expect(cLeft, greaterThan(bLeft));
      expect(eLeft, greaterThan(cLeft));
    },
  );

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
    expect(find.byIcon(Icons.drag_handle), findsNWidgets(2));
    await openEventMenu(tester, 'long-a');
    expect(find.byKey(const ValueKey('move-down-long-a')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('consecutive reorder clicks immediately refresh boundaries', (
    tester,
  ) async {
    final repository = MemoryRepository([
      event('a', 0),
      event('b', 1),
      event('c', 2),
      event('d', 3),
    ]);
    await tester.pumpWidget(JaxApp(repository: repository, now: () => time));
    await tester.pumpAndSettle();
    await openEventsPage(tester);

    await openEventMenu(tester, 'c');
    await tester.tap(find.byKey(const ValueKey('move-up-c')));
    await tester.pumpAndSettle();
    await openEventMenu(tester, 'c');
    await tester.tap(find.byKey(const ValueKey('move-up-c')));
    await tester.pumpAndSettle();
    expect(
      (await repository.getOrderedTopLevelEvents()).map((event) => event.id),
      ['c', 'a', 'b', 'd'],
    );
    await openEventMenu(tester, 'c');
    expect(find.byKey(const ValueKey('move-up-c')), findsNothing);
    expect(find.byKey(const ValueKey('move-down-c')), findsOneWidget);
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();

    await openEventMenu(tester, 'c');
    await tester.tap(find.byKey(const ValueKey('move-down-c')));
    await tester.pumpAndSettle();
    await openEventMenu(tester, 'c');
    await tester.tap(find.byKey(const ValueKey('move-down-c')));
    await tester.pumpAndSettle();
    await openEventMenu(tester, 'c');
    await tester.tap(find.byKey(const ValueKey('move-down-c')));
    await tester.pumpAndSettle();
    expect(
      (await repository.getOrderedTopLevelEvents()).map((event) => event.id),
      ['a', 'b', 'd', 'c'],
    );
    await openEventMenu(tester, 'c');
    expect(find.byKey(const ValueKey('move-up-c')), findsOneWidget);
    expect(find.byKey(const ValueKey('move-down-c')), findsNothing);
  });
}
