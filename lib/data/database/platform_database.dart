import 'dart:io';

import 'android_database.dart';
import 'app_database.dart';
import 'windows_database.dart';

Future<AppDatabase> openPlatformDatabase() {
  if (Platform.isWindows) return openWindowsDatabase();
  if (Platform.isAndroid) return openAndroidDatabase();
  throw UnsupportedError('Jax supports Windows and Android only.');
}
