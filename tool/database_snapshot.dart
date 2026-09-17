import 'dart:io';

import 'package:jax/data/database/app_database.dart';

import 'private_tool_support.dart';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const expectedSchemaVersion = AppDatabase.schemaVersion;

Future<void> main(List<String> arguments) =>
    runPrivateTool(arguments, runSnapshot);

Future<void> runSnapshot(List<String> arguments) async {
  if (arguments.contains("--help") || arguments.contains("-help")) {
    stdout.writeln(
      "Read-only source; snapshot writes a NEW private output. No migration.\nUsage: database_snapshot.dart snapshot|snapshot-any <db> <private-output.db> or verify|verify-any|inspect|inspect-any <db>. Inspect prints no rows. --verbose: private diagnostics.",
    );
    return;
  }
  if (arguments.isEmpty ||
      !{
        'snapshot',
        'snapshot-any',
        'verify',
        'verify-any',
        'inspect',
        'inspect-any',
      }.contains(arguments[0])) {
    stderr.writeln(
      'Usage: dart run tool/database_snapshot.dart <snapshot|snapshot-any|verify|verify-any|inspect|inspect-any> <database> [destination]',
    );
    exitCode = 64;
    return;
  }
  sqfliteFfiInit();
  final requireCurrentSchema = !arguments[0].endsWith('-any');
  if (arguments[0].startsWith('inspect')) {
    if (arguments.length != 2) {
      throw ArgumentError('inspect requires a database path');
    }
    await _verify(arguments[1], requireCurrentSchema: requireCurrentSchema);
    return;
  }
  if (arguments[0].startsWith('verify')) {
    if (arguments.length != 2) {
      stderr.writeln('verify requires a database path');
      exitCode = 64;
      return;
    }
    await _verify(arguments[1], requireCurrentSchema: requireCurrentSchema);
    return;
  }
  if (arguments.length != 3) {
    stderr.writeln('snapshot requires a destination path');
    exitCode = 64;
    return;
  }
  await _snapshot(
    arguments[1],
    arguments[2],
    requireCurrentSchema: requireCurrentSchema,
  );
}

Future<void> _snapshot(
  String source,
  String destination, {
  required bool requireCurrentSchema,
}) async {
  if (!File(source).existsSync()) {
    throw StateError('Source database does not exist: $source');
  }
  requirePrivateOutput(destination);
  final output = File(destination);
  if (output.existsSync()) {
    throw StateError('Snapshot destination already exists: $destination');
  }
  await output.parent.create(recursive: true);
  final database = await databaseFactoryFfi.openDatabase(
    File(source).absolute.path,
    options: OpenDatabaseOptions(readOnly: true),
  );
  try {
    await _verifyOpen(
      database,
      source,
      requireCurrentSchema: requireCurrentSchema,
    );
    final escaped = output.absolute.path.replaceAll("'", "''");
    await database.execute("VACUUM INTO '$escaped'");
  } finally {
    await database.close();
  }
  await _verify(destination, requireCurrentSchema: requireCurrentSchema);
  stdout.writeln('Consistent SQLite snapshot created in private output.');
}

Future<void> _verify(String path, {required bool requireCurrentSchema}) async {
  if (!File(path).existsSync()) {
    throw StateError('Database does not exist: $path');
  }
  final database = await databaseFactoryFfi.openDatabase(
    File(path).absolute.path,
    options: OpenDatabaseOptions(readOnly: true),
  );
  try {
    await _verifyOpen(
      database,
      path,
      requireCurrentSchema: requireCurrentSchema,
    );
  } finally {
    await database.close();
  }
}

Future<void> _verifyOpen(
  Database database,
  String path, {
  required bool requireCurrentSchema,
}) async {
  final version =
      (await database.rawQuery('PRAGMA user_version')).single.values.single
          as int;
  if (requireCurrentSchema && version != expectedSchemaVersion) {
    throw StateError(
      'Schema mismatch for $path: expected $expectedSchemaVersion, found $version',
    );
  }
  final integrity = await database.rawQuery('PRAGMA integrity_check');
  if (integrity.length != 1 || integrity.single.values.single != 'ok') {
    throw StateError('SQLite integrity_check failed for $path: $integrity');
  }
  await database.execute('PRAGMA foreign_keys = ON');
  final foreignKeys = await database.rawQuery('PRAGMA foreign_key_check');
  if (foreignKeys.isNotEmpty) {
    throw StateError('Foreign key violations in $path: $foreignKeys');
  }
  final journal = (await database.rawQuery('PRAGMA journal_mode'))
      .single
      .values
      .single;
  stdout.writeln('Verified schema=$version integrity=ok journal_mode=$journal');
}
