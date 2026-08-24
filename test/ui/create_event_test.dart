import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/app.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/repositories/event_repository.dart';

void main() {
  testWidgets('creates an event without exposing its id', (tester) async {
    final repository = _MemoryRepository();
    await tester.pumpWidget(
      JaxApp(
        repository: repository,
        newId: () => 'hidden-id',
        now: () => DateTime.utc(2026, 8, 24, 12),
      ),
    );
    await tester.pumpAndSettle();

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
    final repository = _MemoryRepository();
    await tester.pumpWidget(JaxApp(repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('新建事件'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();

    expect(find.text('事件名称不能为空'), findsOneWidget);
    expect(repository.events, isEmpty);
  });
}

class _MemoryRepository implements EventRepository {
  final events = <JaxEvent>[];

  @override
  Future<void> insertEvent(JaxEvent event) async => events.add(event);

  @override
  Future<List<JaxEvent>> getIncompleteEvents() async => List.of(events);
}
