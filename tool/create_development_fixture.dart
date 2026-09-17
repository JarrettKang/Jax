import 'dart:convert';
import 'dart:io';

import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/database/development_data_reset.dart';
import 'package:path/path.dart' as p;

import 'private_tool_support.dart';

Future<void> main(List<String> args) => runPrivateTool(args, runCreateFixture);

Future<void> runCreateFixture(List<String> args) async {
  if (args.contains('--help') || args.contains('-help')) {
    stdout.writeln(
      'Create a NEW empty, marked development fixture. Usage: create_development_fixture.dart <private-output.db>. Never overwrites a file.',
    );
    return;
  }
  if (args.length != 1) throw ArgumentError('One explicit output required.');
  final file = File(p.normalize(p.absolute(args.single)));
  final appData = Platform.environment['APPDATA'];
  if (appData != null &&
      (p.isWithin(p.join(appData, 'Jax'), file.path) ||
          p.equals(p.join(appData, 'Jax'), file.path))) {
    throw StateError('Real Jax user-data directory is never a fixture target.');
  }
  requirePrivateOutput(file.path);
  if (file.existsSync() || File('${file.path}.jax-fixture.json').existsSync()) {
    throw StateError('Target must be new.');
  }
  await file.parent.create(recursive: true);
  final app = await AppDatabase.open(file.path);
  try {
    await DevelopmentDataReset(app)
        .run(generation: 'fixture-${DateTime.now().microsecondsSinceEpoch}');
  } finally {
    await app.close();
  }
  await File('${file.path}.jax-fixture.json').writeAsString(
    jsonEncode({
      'owner': 'jax-development-fixture',
      'version': 1,
      'databaseName': p.basename(file.path),
    }),
  );
  stdout.writeln('Empty development fixture created.');
}
