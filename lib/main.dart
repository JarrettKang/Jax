import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'data/database/platform_database.dart';
import 'data/preferences/sqlite_world_category_collapse_store.dart';
import 'data/preferences/sqlite_routine_category_collapse_store.dart';
import 'data/repositories/sqlite_event_repository.dart';
import 'data/services/sqlite_save_service.dart';
import 'core/sync/sync_compare_engine.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final database = await openPlatformDatabase();
  SyncPlan? debugSyncPlan;
  final planPath = Platform.environment['JAX_SYNC_PLAN'];
  if (kDebugMode && Platform.isWindows && planPath != null) {
    debugSyncPlan = SyncPlan.fromJsonString(
      await File(planPath).readAsString(),
    );
  }
  runApp(
    JaxApp(
      repository: SqliteEventRepository(database),
      saveService: SqliteSaveService(database),
      worldCategoryCollapseStore: SqliteWorldCategoryCollapseStore(database),
      routineCategoryCollapseStore: SqliteRoutineCategoryCollapseStore(
        database,
      ),
      debugSyncPlan: debugSyncPlan,
    ),
  );
}
