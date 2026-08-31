import 'dart:convert';
import 'dart:io';

import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/database/world_node_migration_report.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln(
      'Usage: dart run tool/world_node_migration_report.dart <database>',
    );
    exitCode = 64;
    return;
  }
  final app = await AppDatabase.open(args.single);
  try {
    final report = await WorldNodeMigrationReporter(app.database).inspect();
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(report.toJson()));
    if (!report.isExactMigration) exitCode = 2;
  } finally {
    await app.close();
  }
}
