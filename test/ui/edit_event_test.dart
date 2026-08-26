import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/app.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';

import '../support/memory_repository.dart';
import '../support/ui_navigation.dart';

void main() {
  testWidgets('edits a pending event through the UI', (tester) async {
    final time = DateTime.utc(2026, 8, 24, 12);
    final repository = MemoryRepository([
      JaxEvent(
        id: 'one',
        name: '旧名称',
        status: EventStatus.pending,
        createdAt: time,
        updatedAt: time,
      ),
    ]);
    await tester.pumpWidget(JaxApp(repository: repository, now: () => time));
    await tester.pumpAndSettle();
    await openEventsPage(tester);
    await openEventMenu(tester, 'one');
    await tester.tap(find.byKey(const ValueKey('edit-one')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '新名称');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('新名称'), findsOneWidget);
    expect(repository.events.single.name, '新名称');
  });
}
