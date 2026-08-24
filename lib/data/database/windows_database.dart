import 'dart:io';

import 'package:path/path.dart' as path;

import 'app_database.dart';

Future<AppDatabase> openWindowsDatabase() async {
  final appData = Platform.environment['APPDATA'];
  if (appData == null || appData.isEmpty) {
    throw StateError('Windows APPDATA directory is unavailable.');
  }
  final directory = Directory(path.join(appData, 'Jax'));
  await directory.create(recursive: true);
  return AppDatabase.open(path.join(directory.path, 'jax.db'));
}
