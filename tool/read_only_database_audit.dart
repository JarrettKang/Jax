import 'private_tool_support.dart';

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:jax/data/sync/sqlite_sync_readiness.dart';
import 'package:jax/data/sync/sqlite_sync_snapshot_adapter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Recovery audit: never opens through AppDatabase, upgrades, or repairs.
Future<void> main(List<String> args) => runPrivateTool(args, runCommand);

Future<void> runCommand(List<String> args) async {
  if (args.contains("--help") || args.contains("-help")) {
    stdout.writeln(
      "Developer-only read_only_database_audit. See docs/TOOLS.md for commands, private output and safety requirements. --verbose enables private diagnostics.",
    );
    return;
  }
  if (args.length != 2) {
    throw ArgumentError(
      'Usage: read_only_database_audit.dart <db> <new-report.json>',
    );
  }
  final source = File(args[0]).absolute;
  requirePrivateOutput(args[1]);
  final output = File(args[1]).absolute;
  if (!source.existsSync() || output.existsSync()) {
    throw StateError('Source must exist and report destination must be new.');
  }
  final before = sha256.convert(await source.readAsBytes()).toString();
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    source.absolute.path,
    options: OpenDatabaseOptions(readOnly: true),
  );
  try {
    final tables = <String, List<Map<String, Object?>>>{};
    for (final entry in await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
    )) {
      final name = entry['name']! as String;
      final quoted = name.replaceAll('"', '""');
      final rows = await db.rawQuery('SELECT * FROM "$quoted"');
      tables[name] = rows.map((row) => Map<String, Object?>.from(row)).toList()
        ..sort((a, b) => jsonEncode(a).compareTo(jsonEncode(b)));
    }
    final issues = await SqliteSyncReadiness.fromDatabase(db).validate();
    final snapshot = await SqliteSyncSnapshotAdapter(db).read();
    final report = {
      'sha256': before,
      'schemaVersion': (await db.rawQuery('PRAGMA user_version'))
          .single
          .values
          .single,
      'journalMode': (await db.rawQuery('PRAGMA journal_mode'))
          .single
          .values
          .single,
      'integrity': (await db.rawQuery('PRAGMA integrity_check'))
          .single
          .values
          .single,
      'foreignKeyViolations': await db.rawQuery('PRAGMA foreign_key_check'),
      'datasetMetadata': tables['dataset_metadata'],
      'syncProtocol': snapshot.protocolVersion,
      'businessFingerprintSha256': snapshot.businessFingerprintSha256,
      'readiness': [
        for (final issue in issues)
          {
            'code': issue.code,
            'detail': issue.detail,
            'blocking': issue.isBlocking,
          },
      ],
      'counts': {
        for (final entry in tables.entries) entry.key: entry.value.length,
      },
      'tables': tables,
    };
    await output.writeAsString(
      const JsonEncoder.withIndent('  ').convert(report),
    );
    stdout.writeln('AUDIT_OK: full report is private; source bytes unchanged.');
  } finally {
    await db.close();
    if (sha256.convert(await source.readAsBytes()).toString() != before) {
      throw StateError('Audit unexpectedly changed source bytes.');
    }
  }
}
