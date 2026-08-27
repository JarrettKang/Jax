import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:jax/app.dart';
import 'package:jax/core/entities/category.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/preferences/sqlite_world_category_collapse_store.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';
import 'package:jax/data/services/sqlite_save_service.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('World overview and Category detail use real SQLite', (
    tester,
  ) async {
    final databasePath = Platform.isAndroid
        ? path.join(
            await getDatabasesPath(),
            'jax-world-overview-${DateTime.now().microsecondsSinceEpoch}.db',
          )
        : path.join(
            (await Directory.systemTemp.createTemp('jax-world-overview-')).path,
            'jax.db',
          );
    final database = Platform.isAndroid
        ? await AppDatabase.openWithFactory(databasePath, databaseFactory)
        : await AppDatabase.open(databasePath);
    addTearDown(() async {
      await database.close();
      if (Platform.isAndroid) {
        await deleteDatabase(databasePath);
      } else {
        await File(databasePath).parent.delete(recursive: true);
      }
    });
    final now = DateTime.utc(2026, 8, 28, 8);
    final repository = SqliteEventRepository(database);
    for (final category in [
      Category(
        id: 'dev',
        name: '开发项目',
        sortOrder: 0,
        createdAt: now,
        updatedAt: now,
      ),
      Category(
        id: 'research',
        name: '科研',
        sortOrder: 1,
        createdAt: now,
        updatedAt: now,
      ),
      Category(
        id: 'empty',
        name: '生活起居',
        sortOrder: 2,
        createdAt: now,
        updatedAt: now,
      ),
    ]) {
      await repository.insertCategory(category);
    }
    for (final event in [
      JaxEvent(
        id: 'root',
        name: '开发 Jax',
        status: EventStatus.pending,
        categoryId: 'dev',
        createdAt: now,
        updatedAt: now,
      ),
      JaxEvent(
        id: 'existing-child',
        name: '已有下层',
        status: EventStatus.pending,
        parentEventId: 'root',
        createdAt: now,
        updatedAt: now,
      ),
      JaxEvent(
        id: 'completed-child',
        name: '已完成下层',
        status: EventStatus.completed,
        parentEventId: 'root',
        createdAt: now,
        updatedAt: now,
      ),
      JaxEvent(
        id: 'running',
        name: '测试 Yukawa',
        status: EventStatus.running,
        categoryId: 'research',
        firstStartedAt: now,
        createdAt: now,
        updatedAt: now,
      ),
      JaxEvent(
        id: 'loose',
        name: '未分类事件',
        status: EventStatus.waiting,
        createdAt: now,
        updatedAt: now,
      ),
    ]) {
      await repository.insertEvent(event);
    }
    final ids = ['new-root', 'new-child'].iterator;
    await tester.pumpWidget(
      JaxApp(
        repository: repository,
        saveService: SqliteSaveService(database),
        worldCategoryCollapseStore: SqliteWorldCategoryCollapseStore(database),
        newId: () {
          ids.moveNext();
          return ids.current;
        },
        now: () => now,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('世界'));
    await tester.pumpAndSettle();

    for (final id in ['dev', 'research', 'empty', null]) {
      expect(find.byKey(ValueKey('world-category-$id')), findsOne);
    }
    expect(
      find.byKey(const ValueKey('world-category-active-research')),
      findsOne,
    );
    expect(find.text('3 个事件'), findsOne);

    await tester.tap(find.byKey(const ValueKey('world-category-open-dev')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('world-node-root')), findsOne);
    expect(find.byKey(const ValueKey('world-node-running')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('world-batch-select')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Checkbox>(
            find.byKey(const ValueKey('world-batch-checkbox-completed-child')),
          )
          .onChanged,
      isNull,
    );
    await tester.tap(find.byKey(const ValueKey('world-batch-checkbox-root')));
    await tester.tap(
      find.byKey(const ValueKey('world-batch-checkbox-existing-child')),
    );
    await tester.pumpAndSettle();
    expect(find.text('已选择 2 项'), findsOne);
    await tester.tap(find.byKey(const ValueKey('world-batch-add-today')));
    await tester.pumpAndSettle();
    expect(
      (await repository.getEventDayPlans('2026-08-28'))
          .map((plan) => plan.eventId),
      ['running', 'root', 'existing-child'],
    );
    expect((await repository.getEvent('root'))!.parentEventId, isNull);
    expect(
      (await repository.getEvent('existing-child'))!.parentEventId,
      'root',
    );
    await tester.tap(find.text('今日'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('today-event-root')), findsOne);
    expect(find.byKey(const ValueKey('today-event-existing-child')), findsOne);
    await tester.tap(find.text('世界'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('world-category-open-dev')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('world-new-event')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '发布 Windows Debug');
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();
    expect((await repository.getEvent('new-root'))!.categoryId, 'dev');

    await tester.tap(find.byKey(const ValueKey('world-more-root')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('world-create-child-root')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '新增下层');
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();
    expect((await repository.getEvent('new-child'))!.parentEventId, 'root');
    expect(
      (await repository.getDirectChildren('root')).map((event) => event.id),
      ['existing-child', 'completed-child', 'new-child'],
    );

    await tester.tap(find.byKey(const ValueKey('world-back-overview')));
    await tester.pumpAndSettle();
    expect(find.text('5 个事件'), findsOne);
    await tester.tap(find.byKey(const ValueKey('world-category-open-empty')));
    await tester.pumpAndSettle();
    expect(find.text('这个分类还没有事件'), findsOne);
    await tester.tap(find.byKey(const ValueKey('world-back-overview')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('world-category-more-dev')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重命名'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Jax 开发');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('Jax 开发'), findsOne);

    await tester.tap(
      find.byKey(const ValueKey('world-category-more-research')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('上移'));
    await tester.pumpAndSettle();
    expect((await repository.getCategories()).first.id, 'research');

    await tester.tap(find.byKey(const ValueKey('world-category-more-dev')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除分类'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('world-category-dev')), findsNothing);
    expect(find.byKey(const ValueKey('world-category-null')), findsOne);
    expect((await repository.getEvent('root'))!.categoryId, isNull);
    await tester.tap(find.byKey(const ValueKey('world-category-open-null')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('world-node-root')), findsOne);
    expect(tester.takeException(), isNull);
  });
}
