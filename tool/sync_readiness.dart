import 'dart:io';

import 'private_tool_support.dart';

import 'package:jax/data/sync/sqlite_sync_readiness.dart';

Future<void> main(List<String> arguments) =>
    runPrivateTool(arguments, runAudit);

Future<void> runAudit(List<String> arguments) async {
  if (arguments.contains("--help") || arguments.contains("-help")) {
    stdout.writeln(
      "Read-only sync_readiness: <database>. No migration or repair. Unsupported schema fails. --verbose is private diagnostics.",
    );
    return;
  }
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
  final database = await openReadOnly(file.path);
  try {
    final issues = await SqliteSyncReadiness.fromDatabase(database).validate();
    stdout.writeln('Read-only schema verified.');
    if (issues.isEmpty) {
      stdout.writeln('SYNC_READINESS_OK');
      return;
    }
    for (final issue in issues) {
      final output = issue.isBlocking ? stderr : stdout;
      output.writeln('${issue.isBlocking ? 'ERROR' : 'WARNING'} ${issue.code}');
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
