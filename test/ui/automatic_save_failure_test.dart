import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/app.dart';
import 'package:jax/core/entities/jax_event.dart';

import '../support/memory_repository.dart';
import '../support/ui_navigation.dart';

class FailingInsertRepository extends MemoryRepository {
  @override
  Future<void> insertEvent(JaxEvent event) =>
      Future<void>.error(StateError('disk is full'));
}

void main() {
  testWidgets('database failure is shown and is not reported as success', (
    tester,
  ) async {
    final repository = FailingInsertRepository();
    await tester.pumpWidget(
      JaxApp(
        repository: repository,
        newId: () => 'event',
        now: () => DateTime.utc(2026, 8, 24, 12),
      ),
    );
    await tester.pumpAndSettle();
    await openEventsPage(tester);
    await tester.tap(find.text('新建事件'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '无法保存');
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();

    expect(find.text('保存失败，请重试'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(repository.events, isEmpty);
  });
}
