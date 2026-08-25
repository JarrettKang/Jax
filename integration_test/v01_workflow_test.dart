import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:jax/app.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';
import 'package:jax/data/services/sqlite_save_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('v0.1 workflow survives a database restart', (tester) async {
    final directory = await Directory.systemTemp.createTemp('jax-e2e-');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}${Platform.pathSeparator}jax.db';
    var database = await AppDatabase.open(path);
    var repository = SqliteEventRepository(database);
    final ids = <String>[
      'event-a',
      'segment-a-1',
      'event-b',
      'segment-b-1',
      'segment-a-2',
    ].iterator;
    var now = DateTime.utc(2026, 8, 24, 8);
    String newId() {
      if (!ids.moveNext()) throw StateError('Unexpected ID request');
      return ids.current;
    }

    await tester.pumpWidget(
      JaxApp(
        repository: repository,
        saveService: SqliteSaveService(database),
        newId: newId,
        now: () => now,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('我们来做点什么？'), findsOneWidget);
    await tester.tap(find.text('我们来做点什么？'));
    await tester.pumpAndSettle();

    Future<void> create(String name) async {
      await tester.tap(find.text('新建事件'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), name);
      await tester.tap(find.widgetWithText(FilledButton, '创建'));
      await tester.pumpAndSettle();
    }

    await create('任务 A');
    now = now.add(const Duration(minutes: 1));
    await tester.tap(find.byKey(const ValueKey('start-event-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('首页'));
    await tester.pumpAndSettle();
    expect(find.text('当前正在执行：'), findsOneWidget);
    expect(find.text('任务 A'), findsOneWidget);
    await tester.tap(find.text('事件'));
    await tester.pumpAndSettle();
    await create('任务 B');

    await tester.tap(find.byKey(const ValueKey('start-event-b')));
    for (
      var attempt = 0;
      attempt < 20 && find.text('请先暂停或完成当前事件').evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('请先暂停或完成当前事件'), findsOneWidget);

    now = now.add(const Duration(minutes: 9));
    await tester.tap(find.byKey(const ValueKey('pause-event-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('edit-event-a')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '任务 A（已编辑）');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    now = now.add(const Duration(minutes: 1));
    await tester.tap(find.byKey(const ValueKey('start-event-b')));
    await tester.pumpAndSettle();
    now = now.add(const Duration(minutes: 4));
    await tester.tap(find.byKey(const ValueKey('pause-event-b')));
    await tester.pumpAndSettle();

    now = now.add(const Duration(minutes: 2));
    await tester.tap(find.byKey(const ValueKey('resume-event-a')));
    await tester.pumpAndSettle();
    now = now.add(const Duration(minutes: 6));
    await tester.tap(find.byKey(const ValueKey('complete-event-a')));
    await tester.pumpAndSettle();
    expect(find.text('任务 A（已编辑）'), findsNothing);

    await tester.tap(find.text('记录'));
    await tester.pumpAndSettle();
    expect(find.text('任务 A（已编辑）'), findsOneWidget);
    expect(find.textContaining('持续：15 分钟'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('delete-history-event-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(find.text('暂无历史记录'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await database.close();
    database = await AppDatabase.open(path);
    addTearDown(database.close);
    repository = SqliteEventRepository(database);
    await tester.pumpWidget(
      JaxApp(
        repository: repository,
        saveService: SqliteSaveService(database),
        now: () => now,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('事件'));
    await tester.pumpAndSettle();
    expect(find.text('任务 B'), findsOneWidget);
    expect((await repository.getEvent('event-b'))!.status, EventStatus.paused);
  });
}
