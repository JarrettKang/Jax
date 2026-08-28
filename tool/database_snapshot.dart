import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const expectedSchemaVersion = 11;

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty || !{'snapshot', 'snapshot-any', 'verify', 'verify-any', 'inspect'}.contains(arguments[0])) {
    stderr.writeln('Usage: dart run tool/database_snapshot.dart <snapshot|snapshot-any|verify|verify-any|inspect> <database> [destination]');
    exitCode = 64;
    return;
  }
  sqfliteFfiInit();
  final requireCurrentSchema = !arguments[0].endsWith('-any');
  if (arguments[0] == 'inspect') {
    if (arguments.length != 2) { throw ArgumentError('inspect requires a database path'); }
    await _inspect(arguments[1]);
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
  await _snapshot(arguments[1], arguments[2], requireCurrentSchema: requireCurrentSchema);
}

Future<void> _inspect(String path) async {
  final database = await databaseFactoryFfi.openDatabase(path, options: OpenDatabaseOptions(readOnly: true));
  try {
    await _verifyOpen(database, path, requireCurrentSchema: true);
    const tables = ['categories', 'events', 'run_segments', 'routine_categories', 'routines', 'routine_executions', 'routine_run_segments', 'event_day_plans', 'world_category_collapse_preferences', 'routine_category_collapse_preferences'];
    for (final table in tables) {
      final exists = (await database.rawQuery("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", [table])).isNotEmpty;
      if (exists) {
        final count = (await database.rawQuery('SELECT COUNT(*) AS count FROM $table')).single['count'];
        stdout.writeln('$table=$count');
      }
    }
    final runningEvents = (await database.rawQuery("SELECT COUNT(*) AS count FROM events WHERE status = 'running'")).single['count'];
    final runningRoutines = (await database.rawQuery("SELECT COUNT(*) AS count FROM routine_executions WHERE status = 'running'")).single['count'];
    final openEventSegments = (await database.rawQuery('SELECT COUNT(*) AS count FROM run_segments WHERE ended_at_utc IS NULL')).single['count'];
    final openRoutineSegments = (await database.rawQuery('SELECT COUNT(*) AS count FROM routine_run_segments WHERE ended_at_utc IS NULL')).single['count'];
    stdout.writeln('running_events=$runningEvents');
    stdout.writeln('running_routines=$runningRoutines');
    stdout.writeln('open_event_segments=$openEventSegments');
    stdout.writeln('open_routine_segments=$openRoutineSegments');
  } finally { await database.close(); }
}

Future<void> _snapshot(String source, String destination, {required bool requireCurrentSchema}) async {
  if (!File(source).existsSync()) throw StateError('Source database does not exist: $source');
  final output = File(destination);
  if (output.existsSync()) throw StateError('Snapshot destination already exists: $destination');
  await output.parent.create(recursive: true);
  final database = await databaseFactoryFfi.openDatabase(source, options: OpenDatabaseOptions(readOnly: true));
  try {
    await _verifyOpen(database, source, requireCurrentSchema: requireCurrentSchema);
    final escaped = destination.replaceAll("'", "''");
    await database.execute("VACUUM INTO '$escaped'");
  } finally {
    await database.close();
  }
  await _verify(destination, requireCurrentSchema: requireCurrentSchema);
  stdout.writeln('Consistent SQLite snapshot created: $destination');
}

Future<void> _verify(String path, {required bool requireCurrentSchema}) async {
  if (!File(path).existsSync()) throw StateError('Database does not exist: $path');
  final database = await databaseFactoryFfi.openDatabase(path, options: OpenDatabaseOptions(readOnly: true));
  try {
    await _verifyOpen(database, path, requireCurrentSchema: requireCurrentSchema);
  } finally {
    await database.close();
  }
}

Future<void> _verifyOpen(Database database, String path, {required bool requireCurrentSchema}) async {
  final version = (await database.rawQuery('PRAGMA user_version'))
      .single
      .values
      .single as int;
  if (requireCurrentSchema && version != expectedSchemaVersion) {
    throw StateError('Schema mismatch for $path: expected $expectedSchemaVersion, found $version');
  }
  final integrity = await database.rawQuery('PRAGMA integrity_check');
  if (integrity.length != 1 || integrity.single.values.single != 'ok') {
    throw StateError('SQLite integrity_check failed for $path: $integrity');
  }
  await database.execute('PRAGMA foreign_keys = ON');
  final foreignKeys = await database.rawQuery('PRAGMA foreign_key_check');
  if (foreignKeys.isNotEmpty) throw StateError('Foreign key violations in $path: $foreignKeys');
  final journal = (await database.rawQuery('PRAGMA journal_mode')).single.values.single;
  stdout.writeln('Verified schema=$version integrity=ok journal_mode=$journal: $path');
}
