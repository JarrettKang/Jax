import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/app.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/services/save_service.dart';

import '../support/memory_repository.dart';
import '../support/ui_navigation.dart';

class MutableSaveService implements SaveService {
  Object? error;

  @override
  Future<void> flush() async {
    if (error != null) throw error!;
  }
}

class FailingAfterFirstInsertRepository extends MemoryRepository {
  var fail = false;

  @override
  Future<void> insertEvent(JaxEvent event) async {
    if (fail) throw StateError('disk is full');
    await super.insertEvent(event);
  }
}

void main() {
  testWidgets('automatic save success updates last saved time', (tester) async {
    var clock = DateTime(2026, 8, 25, 21, 15, 3);
    await tester.pumpWidget(
      JaxApp(
        repository: MemoryRepository(),
        newId: () => 'event',
        now: () => clock,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('已加载本地数据'), findsOneWidget);

    await _createEvent(tester, '自动保存');

    expect(find.text('最后保存：21:15:03'), findsOneWidget);
  });

  testWidgets('manual save success updates last saved time', (tester) async {
    var clock = DateTime(2026, 8, 25, 21, 18, 32);
    await tester.pumpWidget(
      JaxApp(
        repository: MemoryRepository(),
        saveService: MutableSaveService(),
        now: () => clock,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('manual-save')));
    await tester.pumpAndSettle();

    expect(find.text('最后保存：21:18:32'), findsOneWidget);
  });

  testWidgets('failed manual save retains the previous successful time', (
    tester,
  ) async {
    var clock = DateTime(2026, 8, 25, 21, 18, 32);
    final saveService = MutableSaveService();
    await tester.pumpWidget(
      JaxApp(
        repository: MemoryRepository(),
        saveService: saveService,
        newId: () => 'event',
        now: () => clock,
      ),
    );
    await tester.pumpAndSettle();
    await _createEvent(tester, '上一次自动保存');

    clock = DateTime(2026, 8, 25, 22, 0);
    saveService.error = StateError('disk is full');
    await tester.tap(find.byKey(const ValueKey('manual-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('保存失败，请重试'), findsOneWidget);
    expect(find.text('最后保存：21:18:32'), findsOneWidget);
    expect(find.text('最后保存：22:00:00'), findsNothing);
  });

  testWidgets('failed automatic save retains the previous successful time', (
    tester,
  ) async {
    var clock = DateTime(2026, 8, 25, 8, 0, 1);
    final repository = FailingAfterFirstInsertRepository();
    var id = 0;
    await tester.pumpWidget(
      JaxApp(
        repository: repository,
        newId: () => 'event-${id++}',
        now: () => clock,
      ),
    );
    await tester.pumpAndSettle();
    await _createEvent(tester, '第一次成功');
    expect(find.text('最后保存：08:00:01'), findsOneWidget);

    repository.fail = true;
    clock = DateTime(2026, 8, 25, 9);
    await _createEvent(tester, '第二次失败');

    expect(find.text('保存失败，请重试'), findsOneWidget);
    expect(find.text('最后保存：08:00:01'), findsOneWidget);
  });

  testWidgets('consecutive successful saves show the latest clock value', (
    tester,
  ) async {
    var clock = DateTime(2026, 8, 25, 10, 11, 12);
    final saveService = MutableSaveService();
    await tester.pumpWidget(
      JaxApp(
        repository: MemoryRepository(),
        saveService: saveService,
        now: () => clock,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('manual-save')));
    await tester.pumpAndSettle();
    expect(find.text('最后保存：10:11:12'), findsOneWidget);

    clock = DateTime(2026, 8, 25, 13, 14, 15);
    await tester.tap(find.byKey(const ValueKey('manual-save')));
    await tester.pumpAndSettle();

    expect(find.text('最后保存：13:14:15'), findsOneWidget);
    expect(find.text('最后保存：10:11:12'), findsNothing);
  });
}

Future<void> _createEvent(WidgetTester tester, String name) async {
  await openEventsPage(tester);
  await tester.tap(find.byKey(const ValueKey('add-standalone-event')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('standalone-event-name')),
    name,
  );
  await tester.tap(find.byKey(const ValueKey('save-standalone-event')));
  await tester.pumpAndSettle();
}
