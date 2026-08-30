import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:jax/app.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/category.dart';
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
    var nextId = 0;
    var now = DateTime.utc(2026, 8, 24, 8);
    String newId() {
      return 'workflow-${nextId++}';
    }

    await repository.insertCategory(
      Category(
        id: 'workflow-category',
        name: '验收分类',
        sortOrder: 0,
        createdAt: now,
        updatedAt: now,
      ),
    );

    await tester.pumpWidget(
      JaxApp(
        repository: repository,
        saveService: SqliteSaveService(database),
        newId: newId,
        now: () => now,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('世界'));
    await tester.pumpAndSettle();

    Future<String> create(String name) async {
      if (find.byKey(const ValueKey('world-new-event')).evaluate().isEmpty) {
        await tester.tap(
          find.byKey(const ValueKey('world-category-open-workflow-category')),
        );
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const ValueKey('world-new-event')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), name);
      await tester.tap(find.widgetWithText(FilledButton, '创建'));
      await tester.pumpAndSettle();
      return (await repository.getIncompleteEvents())
          .singleWhere((event) => event.name == name)
          .id;
    }

    Future<void> action(
      String eventId,
      String actionKey, {
      bool settle = true,
    }) async {
      await tester.tap(find.byKey(ValueKey('world-more-$eventId')));
      await tester.pumpAndSettle();
      final item = find.byKey(ValueKey('$actionKey-$eventId'));
      await tester.ensureVisible(item);
      await tester.pump();
      await tester.tap(item);
      if (settle) {
        await tester.pumpAndSettle();
      } else {
        await tester.pump();
      }
    }

    final eventAId = await create('任务 A');
    now = now.add(const Duration(minutes: 1));
    await action(eventAId, 'start');
    await tester.tap(find.text('首页'));
    await tester.pumpAndSettle();
    expect(find.text('正在执行'), findsOneWidget);
    expect(find.text('任务 A'), findsWidgets);
    await tester.tap(find.text('世界'));
    await tester.pumpAndSettle();
    final eventBId = await create('任务 B');

    await action(eventBId, 'start', settle: false);
    await tester.pump(const Duration(seconds: 1));
    expect((await repository.getEvent(eventAId))!.status, EventStatus.running);
    expect((await repository.getEvent(eventBId))!.status, EventStatus.pending);

    now = now.add(const Duration(minutes: 9));
    await action(eventAId, 'pause');
    await tester.tap(find.byKey(ValueKey('world-more-$eventAId')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('edit-$eventAId')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '任务 A（已编辑）');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    now = now.add(const Duration(minutes: 1));
    await action(eventBId, 'start');
    now = now.add(const Duration(minutes: 4));
    await action(eventBId, 'pause');

    now = now.add(const Duration(minutes: 2));
    await action(eventAId, 'resume');
    now = now.add(const Duration(minutes: 6));
    await action(eventAId, 'complete');
    expect(find.text('任务 A（已编辑）'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('world-more-$eventAId')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('world-delete-history-$eventAId')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(find.text('任务 A（已编辑）'), findsNothing);

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

    await tester.tap(find.text('世界'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('world-category-open-workflow-category')),
    );
    await tester.pumpAndSettle();
    expect(find.text('任务 B'), findsOneWidget);
    expect((await repository.getEvent(eventBId))!.status, EventStatus.paused);
  });
}
