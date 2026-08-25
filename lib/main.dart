import 'package:flutter/material.dart';

import 'app.dart';
import 'data/database/platform_database.dart';
import 'data/repositories/sqlite_event_repository.dart';
import 'data/services/sqlite_save_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final database = await openPlatformDatabase();
  runApp(
    JaxApp(
      repository: SqliteEventRepository(database),
      saveService: SqliteSaveService(database),
    ),
  );
}
