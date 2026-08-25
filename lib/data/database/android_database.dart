import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

Future<AppDatabase> openAndroidDatabase() async {
  final directory = await getDatabasesPath();
  return AppDatabase.openWithFactory(
    path.join(directory, 'jax.db'),
    databaseFactory,
  );
}
