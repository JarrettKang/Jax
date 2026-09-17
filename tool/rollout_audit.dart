import 'private_tool_support.dart';

import 'dart:convert';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _businessTables = [
  'categories',
  'routine_categories',
  'world_nodes',
  'plans',
  'plan_items',
  'plan_review_notes',
  'events',
  'event_day_plans',
  'run_segments',
  'routines',
  'routine_executions',
  'routine_run_segments',
  'sync_tombstones',
  'dataset_metadata',
];

Future<void> main(List<String> arguments) =>
    runPrivateTool(arguments, runCommand);

Future<void> runCommand(List<String> arguments) async {
  if (arguments.contains("--help") || arguments.contains("-help")) {
    stdout.writeln(
      "Developer-only rollout_audit. See docs/TOOLS.md for commands, private output and safety requirements. --verbose enables private diagnostics.",
    );
    return;
  }
  if (arguments.length != 2) {
    stderr.writeln(
      'Usage: dart run tool/rollout_audit.dart <database> <output.json>',
    );
    exitCode = 64;
    return;
  }
  requirePrivateOutput(arguments[1]);
  if (File(arguments[1]).existsSync()) throw StateError("Output must be new.");
  sqfliteFfiInit();
  final database = await databaseFactoryFfi.openDatabase(
    File(arguments[0]).absolute.path,
    options: OpenDatabaseOptions(readOnly: true),
  );
  try {
    final tables = <String, List<Map<String, Object?>>>{};
    for (final table in _businessTables) {
      if (!await _tableExists(database, table)) continue;
      final rows = [
        for (final row in await database.query(table))
          Map<String, Object?>.from(row),
      ];
      rows.sort((left, right) => jsonEncode(left).compareTo(jsonEncode(right)));
      tables[table] = rows;
    }
    final integrity = await database.rawQuery('PRAGMA integrity_check');
    final foreignKeys = await database.rawQuery('PRAGMA foreign_key_check');
    final version = (await database.rawQuery('PRAGMA user_version'))
        .single
        .values
        .single;
    final output = <String, Object?>{
      'schemaVersion': version,
      'integrity': integrity.single.values.single,
      'foreignKeyViolations': foreignKeys,
      'counts': {
        for (final entry in tables.entries) entry.key: entry.value.length,
      },
      'running': [
        for (final table in ['events', 'routine_executions'])
          if (tables.containsKey(table))
            ...tables[table]!
                .where((row) => row['status'] == 'running')
                .map((row) => {'table': table, 'row': row}),
      ],
      'openSegments': [
        for (final table in ['run_segments', 'routine_run_segments'])
          if (tables.containsKey(table))
            ...tables[table]!
                .where((row) => row['ended_at_utc'] == null)
                .map((row) => {'table': table, 'row': row}),
      ],
      'today': tables['event_day_plans'] ?? const [],
      'recordFacts': [
        ...?tables['run_segments'],
        ...?tables['routine_run_segments'],
      ],
      'tables': tables,
    };
    await File(arguments[1]).writeAsString(
      const JsonEncoder.withIndent('  ').convert(output),
      flush: true,
    );
    stdout.writeln(
      'ROLLOUT_AUDIT_OK schema=$version integrity=${output['integrity']} '
      'fk=${foreignKeys.length}',
    );
  } finally {
    await database.close();
  }
}

Future<bool> _tableExists(Database database, String table) async =>
    (await database.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
      [table],
    )).isNotEmpty;
