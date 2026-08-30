import 'dart:io';

import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/sync/sqlite_sync_readiness.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart run tool/sync_readiness.dart <database>');
    exitCode = 64;
    return;
  }
  final file = File(arguments.single);
  if (!file.existsSync()) {
    stderr.writeln('Database does not exist: ${file.path}');
    exitCode = 66;
    return;
  }
  final database = await AppDatabase.open(file.path);
  try {
    final issues = await SqliteSyncReadiness(database).validate();
    stdout.writeln('schema=${AppDatabase.schemaVersion}');
    if (issues.isEmpty) {
      stdout.writeln('SYNC_READINESS_OK');
      return;
    }
    for (final issue in issues) {
      final output = issue.isBlocking ? stderr : stdout;
      output.writeln('${issue.isBlocking ? 'ERROR' : 'WARNING'} $issue');
    }
    if (issues.any((issue) => issue.isBlocking)) {
      exitCode = 1;
    } else {
      stdout.writeln('SYNC_READINESS_OK_WITH_WARNINGS');
    }
  } finally {
    await database.close();
  }
}
