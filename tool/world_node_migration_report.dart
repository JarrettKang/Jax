import 'dart:io';

import 'private_tool_support.dart';

import 'package:jax/data/database/world_node_migration_report.dart';

Future<void> main(List<String> args) => runPrivateTool(args, runAudit);

Future<void> runAudit(List<String> args) async {
  if (args.contains("--help") || args.contains("-help")) {
    stdout.writeln(
      "Read-only world_node_migration_report: <database>. No migration or repair. Unsupported schema fails. --verbose is private diagnostics.",
    );
    return;
  }
  if (args.length != 1) {
    stderr.writeln(
      'Usage: dart run tool/world_node_migration_report.dart <database>',
    );
    exitCode = 64;
    return;
  }
  final app = await openReadOnly(args.single, currentSchema: false);
  try {
    final report = await WorldNodeMigrationReporter(app).inspect();
    stdout.writeln('MIGRATION_EXACT=${report.isExactMigration}');
    if (!report.isExactMigration) exitCode = 2;
  } finally {
    await app.close();
  }
}
