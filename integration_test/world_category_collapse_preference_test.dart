import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:jax/app.dart';
import 'package:jax/core/entities/category.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/preferences/world_category_collapse_store.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/preferences/sqlite_world_category_collapse_store.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';
import 'package:jax/data/services/sqlite_save_service.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'legacy Category collapse preference is harmless in two-level World',
    (tester) async {
      final databasePath = Platform.isAndroid
          ? path.join(
              await getDatabasesPath(),
              'jax-world-legacy-${DateTime.now().microsecondsSinceEpoch}.db',
            )
          : path.join(
              (await Directory.systemTemp.createTemp('jax-world-legacy-')).path,
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
          name: '科研事件',
          status: EventStatus.pending,
          categoryId: 'research',
          createdAt: now,
          updatedAt: now,
        ),
      );
      final preferences = SqliteWorldCategoryCollapseStore(database);
      await preferences.setCollapsed(
        WorldCategoryCollapseStore.sectionKey('research'),
        true,
      );

      await tester.pumpWidget(
        JaxApp(
          repository: repository,
          saveService: SqliteSaveService(database),
          worldCategoryCollapseStore: preferences,
          now: () => now,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('世界'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('world-category-research')), findsOne);
      await tester.tap(
        find.byKey(const ValueKey('world-category-open-research')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('world-node-root')), findsOne);
      expect(tester.takeException(), isNull);
    },
  );
}
