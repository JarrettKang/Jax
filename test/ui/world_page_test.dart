import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:jax/app.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';

import '../support/memory_repository.dart';

void main() {
  final now = DateTime(2026, 8, 26, 12);
  JaxEvent event(String id, EventStatus status, {String? parent, int? order}) =>
      JaxEvent(
        id: id,
        name: id,
        status: status,
        parentEventId: parent,
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
    }
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('world-node-B'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('world-node-C'))).dy,
      ),
    );
    expect(find.text('已完成'), findsOneWidget);
    expect(find.text('等待中'), findsOneWidget);
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
}
