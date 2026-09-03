import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:jax/app.dart';
import 'package:jax/core/entities/category.dart';
import 'package:jax/core/entities/world_node.dart';
import 'package:jax/core/preferences/world_category_collapse_store.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/preferences/sqlite_world_category_collapse_store.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';
import 'package:jax/data/repositories/sqlite_planning_repository.dart';
import 'package:jax/data/repositories/sqlite_world_node_repository.dart';
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
      final planning = SqlitePlanningRepository(database);
      final worldNodes = SqliteWorldNodeRepository(database);
      await repository.insertCategory(
        Category(
          id: 'research',
          name: '科研',
          sortOrder: 0,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await worldNodes.insertWorldNode(
        WorldNode(
          id: '00000000-0000-4000-8000-000000000001',
          name: '科研节点',
          status: WorldNodeStatus.inProgress,
          isFocused: false,
          categoryId: 'research',
          sortOrder: 0,
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
          planningRepository: planning,
          worldNodeRepository: worldNodes,
          now: () => now,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('世界'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('world-category-research')), findsOne);
      expect(
        find.byKey(
          const ValueKey('world-node-00000000-0000-4000-8000-000000000001'),
        ),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('world-category-research')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(
          const ValueKey('world-node-00000000-0000-4000-8000-000000000001'),
        ),
        findsOne,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
