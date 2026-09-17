import 'private_tool_support.dart';

import 'dart:io';

import 'package:jax/core/sync/sync_compare_engine.dart';
import 'package:jax/core/sync/sync_contract.dart';
import 'package:jax/data/sync/sqlite_sync_snapshot_adapter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main(List<String> args) => runPrivateTool(args, runCommand);

Future<void> runCommand(List<String> args) async {
  if (args.contains("--help") || args.contains("-help")) {
    stdout.writeln(
      "Developer-only sync_phase2a. See docs/TOOLS.md for commands, private output and safety requirements. --verbose enables private diagnostics.",
    );
    return;
  }
  if (args.isEmpty) return _usage();
  switch (args.first) {
    case 'export' when args.length == 3:
      await _export(args[1], args[2]);
    case 'compare' when args.length == 4 || args.length == 5:
      await _compare(
        args[1],
        args[2],
        args[3],
        args.length == 5 ? args[4] : null,
      );
    case 'fingerprint'
        when args.length == 3 && args.last == '--machine-private':
      stdout.write(
        SyncSnapshot.fromJsonString(File(args[1]).readAsStringSync())
            .businessFingerprint,
      );
    default:
      _usage();
  }
}

void _usage() {
  stderr.writeln('''Phase 2A preview only; no database writes.
Usage:
  dart run tool/sync_phase2a.dart export <read-only.db> <snapshot.json>
  dart run tool/sync_phase2a.dart compare <windows.json> <android.json> <plan.json> [baseline.json]
  dart run tool/sync_phase2a.dart fingerprint <snapshot.json>''');
  exitCode = 64;
}

Future<void> _export(String source, String destination) async {
  if (!File(source).existsSync()) {
    throw StateError('Database does not exist: $source');
  }
  sqfliteFfiInit();
  final database = await databaseFactoryFfi.openDatabase(
    File(source).absolute.path,
    options: OpenDatabaseOptions(readOnly: true),
  );
  try {
    final snapshot = await SqliteSyncSnapshotAdapter(database).read();
    requirePrivateOutput(destination);
    final output = File(destination);
    await output.parent.create(recursive: true);
    await output.writeAsString(snapshot.toJsonString(pretty: true));
    stdout.writeln(
      'SYNC_SNAPSHOT_OK records=${snapshot.records.length} lists=${snapshot.lists.length} warnings=${snapshot.warnings.length}',
    );
  } finally {
    await database.close();
  }
}

Future<void> _compare(
  String windowsPath,
  String androidPath,
  String outputPath,
  String? baselinePath,
) async {
  SyncSnapshot load(String path) =>
      SyncSnapshot.fromJsonString(File(path).readAsStringSync());
  final plan = const SyncCompareEngine().compare(
    windows: load(windowsPath),
    android: load(androidPath),
    baseline: baselinePath == null ? null : load(baselinePath),
  );
  requirePrivateOutput(outputPath);
  final output = File(outputPath);
  await output.parent.create(recursive: true);
  await output.writeAsString(plan.toJsonString());
  final summary = plan.toJson()['summary'];
  stdout.writeln('SYNC_COMPARE_OK previewOnly=true');
  stdout.writeln(summary);
  stdout.writeln('Plan written to private output.');
}
