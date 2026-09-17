import 'dart:io';

import 'package:jax/data/database/app_database.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Tools never open through AppDatabase.open: that would migrate the source.
Future<Database> openReadOnly(
  String filename, {
  bool currentSchema = true,
}) async {
  if (!File(filename).existsSync()) {
    throw StateError('Input database is missing.');
  }
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    p.normalize(p.absolute(filename)),
    options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
  );
  try {
    if (currentSchema) await requireCurrentSchema(db);
    return db;
  } catch (_) {
    await db.close();
    rethrow;
  }
}

Future<void> requireCurrentSchema(Database db) async {
  final version = (await db.rawQuery('PRAGMA user_version'))
      .single
      .values
      .single;
  if (version != AppDatabase.schemaVersion) {
    throw StateError(
      'Unsupported schema. Upgrade a disposable copy with the app; this tool never migrates.',
    );
  }
}

void requirePrivateOutput(String filename) {
  final full = p.normalize(p.absolute(filename));
  var repo = p.normalize(Directory.current.absolute.path);
  while (!File(p.join(repo, 'pubspec.yaml')).existsSync() &&
      p.dirname(repo) != repo) {
    repo = p.dirname(repo);
  }
  if (p.isWithin(repo, full)) {
    final first = p.split(p.relative(full, from: repo)).first;
    if (![
      '.local_private',
      '.debug_backups',
      '.debug_snapshots',
    ].contains(first)) {
      throw StateError(
        'Repository outputs must be inside a private runtime directory.',
      );
    }
  }
  rejectLinks(full);
}

void rejectLinks(String filename) {
  var cursor = p.normalize(p.absolute(filename));
  while (true) {
    if (FileSystemEntity.typeSync(cursor, followLinks: false) ==
        FileSystemEntityType.link) {
      throw StateError('Links are not allowed for tool targets.');
    }
    final parent = p.dirname(cursor);
    if (parent == cursor) break;
    cursor = parent;
  }
}

Future<void> runPrivateTool(
  List<String> args,
  Future<void> Function(List<String>) body,
) async {
  final verbose = args.contains('--verbose');
  try {
    await body(args.where((arg) => arg != '--verbose').toList());
  } catch (error, stack) {
    stderr.writeln(
      verbose ? '$error\n$stack' : 'Tool failed; no automatic repair. Use --verbose only in a private terminal for diagnostic details.',
    );
    exitCode = 1;
  }
}
