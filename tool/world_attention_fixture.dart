import 'dart:io';

import 'package:flutter/material.dart';
import 'package:jax/app.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/preferences/sqlite_world_category_collapse_store.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';
import 'package:jax/data/repositories/sqlite_planning_repository.dart';
import 'package:jax/data/repositories/sqlite_world_node_repository.dart';
import 'package:jax/ui/controllers/planning_controller.dart';
import 'package:jax/ui/pages/world_page.dart';
import 'package:sqflite/sqflite.dart';

import '../test/support/world_map_fixture.dart';

/// Install only as com.jarrett.jax.worldfixture through the guarded installer.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final directory = await Directory.systemTemp.createTemp('world-qa-');
  final file = '${directory.path}/fixture.db';
  final app = Platform.isAndroid
      ? await AppDatabase.openWithFactory(file, databaseFactory)
      : await AppDatabase.open(file);
  await seedWorldMapFixture(app);
  final controller = PlanningController(
    planningRepository: SqlitePlanningRepository(app),
    worldNodeRepository: SqliteWorldNodeRepository(app),
    eventRepository: SqliteEventRepository(app),
    newId: () => 'fixture-${DateTime.now().microsecondsSinceEpoch}',
    now: DateTime.now,
  );
  controller.addListener(() {
    debugPrint(
      'WORLD_QA_FOCUS: ${controller.worldNodes.where((n) => n.isFocused).map((n) => n.name).join(', ')}',
    );
  });
  runApp(
    MaterialApp(
      theme: buildJaxTheme(
        Platform.isWindows ? TargetPlatform.windows : TargetPlatform.android,
      ),
      home: Scaffold(
        appBar: AppBar(title: const Text('World 手势验收 · 隔离数据')),
        body: WorldPage(
          controller: controller,
          worldCategoryCollapseStore: SqliteWorldCategoryCollapseStore(app),
        ),
      ),
    ),
  );
}
