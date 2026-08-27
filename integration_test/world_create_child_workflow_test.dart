import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:jax/app.dart';
import 'package:jax/core/entities/category.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';
import 'package:jax/data/services/sqlite_save_service.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('World creates a child from its parent menu on real SQLite', (
    tester,
  ) async {
    final databasePath = Platform.isAndroid
        ? path.join(
            await getDatabasesPath(),
            'jax-create-child-${DateTime.now().microsecondsSinceEpoch}.db',
          )
        : path.join(
            (await Directory.systemTemp.createTemp('jax-create-child-')).path,
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
    await repository.insertCategory(
      Category(
        id: 'research',
        name: '科研',
        sortOrder: 0,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await repository.insertEvent(
      JaxEvent(
        id: 'root',
        name: '上层事件',
        status: EventStatus.pending,
        categoryId: 'research',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await repository.insertEvent(
      JaxEvent(
        id: 'existing',
        name: '已有下层',
        status: EventStatus.pending,
        parentEventId: 'root',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await repository.insertEvent(
      JaxEvent(
        id: 'completed',
        name: '完成事件',
        status: EventStatus.completed,
        createdAt: now,
        updatedAt: now,
      ),
    );

    await tester.pumpWidget(
      JaxApp(
        repository: repository,
        saveService: SqliteSaveService(database),
        newId: () => 'new-child',
        now: () => now,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('世界'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('world-more-root')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('world-create-child-root')));
    await tester.pumpAndSettle();
    expect(find.text('由上层事件继承'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('world-create-child-parent')),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField), '新建下层');
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();

    final child = (await repository.getEvent('new-child'))!;
    expect(child.parentEventId, 'root');
    expect(child.categoryId, isNull);
    expect(
      (await repository.getDirectChildren('root')).map((event) => event.id),
      ['existing', 'new-child'],
    );
    expect(await repository.getEventDayPlans('2026-08-28'), isEmpty);
    expect(find.byKey(const ValueKey('world-node-new-child')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('world-more-completed')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('world-create-child-completed')),
      findsNothing,
    );
  });
}
