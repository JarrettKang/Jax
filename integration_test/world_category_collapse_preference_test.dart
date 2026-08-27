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

  testWidgets('World Category collapse survives navigation and app restart', (
    tester,
  ) async {
    final databasePath = Platform.isAndroid
        ? path.join(
            await getDatabasesPath(),
            'jax-world-collapse-${DateTime.now().microsecondsSinceEpoch}.db',
          )
        : path.join(
            (await Directory.systemTemp.createTemp('jax-world-collapse-')).path,
            'jax.db',
          );

    Future<AppDatabase> openDatabase() => Platform.isAndroid
        ? AppDatabase.openWithFactory(databasePath, databaseFactory)
        : AppDatabase.open(databasePath);

    var database = await openDatabase();
    addTearDown(() async {
      await database.close();
      if (Platform.isAndroid) {
        await deleteDatabase(databasePath);
      } else {
        await File(databasePath).parent.delete(recursive: true);
      }
    });
    final now = DateTime.utc(2026, 8, 27, 8);
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
        id: 'research-event',
        name: '科研事件',
        status: EventStatus.pending,
        categoryId: 'research',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await repository.insertEvent(
      JaxEvent(
        id: 'unclassified-event',
        name: '未分类事件',
        status: EventStatus.pending,
        createdAt: now,
        updatedAt: now,
      ),
    );

    Future<void> pumpApp(AppDatabase appDatabase) => tester.pumpWidget(
      JaxApp(
        repository: SqliteEventRepository(appDatabase),
        saveService: SqliteSaveService(appDatabase),
        worldCategoryCollapseStore: SqliteWorldCategoryCollapseStore(
          appDatabase,
        ),
        now: () => now,
      ),
    );

    await pumpApp(database);
    await tester.pumpAndSettle();
    await tester.tap(find.text('世界'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('world-node-research-event')), findsOne);
    expect(
      find.byKey(const ValueKey('world-node-unclassified-event')),
      findsOne,
    );

    await tester.tap(
      find.byKey(const ValueKey('world-category-toggle-research')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('world-node-research-event')),
      findsNothing,
    );
    await tester.tap(find.text('今日'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('世界'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('world-node-research-event')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('world-node-unclassified-event')),
      findsOne,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await database.close();
    database = await openDatabase();
    await pumpApp(database);
    await tester.pumpAndSettle();
    await tester.tap(find.text('世界'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('world-node-research-event')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('world-node-unclassified-event')),
      findsOne,
    );
  });
}
