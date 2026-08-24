import 'package:flutter/material.dart';

import 'app.dart';
import 'data/database/windows_database.dart';
import 'data/repositories/sqlite_event_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final database = await openWindowsDatabase();
  runApp(JaxApp(repository: SqliteEventRepository(database)));
}
