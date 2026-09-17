import 'dart:convert';
import 'dart:io';

import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/database/development_data_reset.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'database_snapshot.dart' as snapshots;
import 'private_tool_support.dart';

Future<void> main(List<String> args) => runPrivateTool(args, runReset);

Future<void> runReset(List<String> args) async {
  if (args.contains('--help') || args.contains('-help')) {
    stdout.writeln(
      'WARNING developer-only destructive fixture reset.\nUsage: development_data_reset.dart <fixture.db> <fixture-generation> [--apply --confirm-destructive-reset]\nDefault PLAN only. Requires create_development_fixture marker and fixture generation. Real user data is always refused. Backup is automatic and verified before reset.',
    );
    return;
  }
  final positional = args.where((a) => !a.startsWith('--')).toList();
  if (positional.length != 2 ||
      args.any(
        (a) =>
            a.startsWith('--') &&
            !['--apply', '--confirm-destructive-reset'].contains(a),
      )) {
    throw ArgumentError(
      'Explicit fixture path and generation required. See --help.',
    );
  }
  final filename = p.normalize(p.absolute(positional[0]));
  rejectLinks(filename);
  final appData = Platform.environment['APPDATA'];
  if (appData != null &&
      (p.isWithin(p.join(appData, 'Jax'), filename) ||
          p.equals(p.join(appData, 'Jax'), filename))) {
    throw StateError('Real Jax user-data directory is never a reset target.');
  }
  requirePrivateOutput(filename);
  if (!positional[1].startsWith('fixture-')) {
    throw StateError('Generation must begin fixture-.');
  }
  final markerPath = '$filename.jax-fixture.json';
  rejectLinks(markerPath);
  final marker = jsonDecode(await File(markerPath).readAsString()) as Map;
  if (marker['owner'] != 'jax-development-fixture' ||
      marker['version'] != 1 ||
      marker['databaseName'] != p.basename(filename)) {
    throw StateError('A valid development-fixture marker is required.');
  }
  final source = await openReadOnly(filename);
  try {
    final generation = (await source.query('dataset_metadata'))
        .single['generation'];
    if (generation is! String || !generation.startsWith('fixture-')) {
      throw StateError('Database identity is not a development fixture.');
    }
  } finally {
    await source.close();
  }
  stdout.writeln(
    'PLAN: reset development fixture\nTARGET: <private-fixture>\nCHANGES: delete business entities, execution facts and tombstones\nSAFETY CHECKS: fixture identity, current schema, verified new backup',
  );
  if (!args.contains('--apply') ||
      !args.contains('--confirm-destructive-reset')) {
    stdout.writeln(
      'DRY_RUN: both destructive flags required; no data changed.',
    );
    return;
  }
  final backupDir = Directory(
    p.join(p.dirname(filename), '.local_private', 'backups'),
  );
  requirePrivateOutput(p.join(backupDir.path, 'probe'));
  await backupDir.create(recursive: true);
  final backupSession = await backupDir.createTemp('jax-reset-');
  final backup = p.join(backupSession.path, 'before.db');
  await snapshots.runSnapshot(['snapshot', filename, backup]);
  await snapshots.runSnapshot(['verify', backup]);
  final db = await databaseFactoryFfi.openDatabase(
    filename,
    options: OpenDatabaseOptions(singleInstance: false),
  );
  try {
    await requireCurrentSchema(db);
    final generation = (await db.query('dataset_metadata'))
        .single['generation'];
    if (generation is! String || !generation.startsWith('fixture-')) {
      throw StateError('Fixture identity changed.');
    }
    await DevelopmentDataReset(AppDatabase.fromOpenDatabase(db))
        .run(generation: positional[1]);
  } finally {
    await db.close();
  }
  stdout.writeln(
    'RESET_COMPLETE; verified pre-reset backup retained privately.',
  );
}
