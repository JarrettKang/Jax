import 'dart:io';

import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/database/development_data_reset.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2 || arguments.contains('--help')) {
    stderr.writeln(
      'Usage: dart run tool/development_data_reset.dart <database> <generation>',
    );
    exitCode = 64;
    return;
  }
  final app = await AppDatabase.open(arguments[0]);
  try {
    final reset = DevelopmentDataReset(app);
    await reset.run(generation: arguments[1]);
    final version = (await app.database.rawQuery('PRAGMA user_version'))
        .single
        .values
        .single;
    stdout.writeln('schema=$version generation=${arguments[1]}');
    for (final entry in (await reset.businessCounts()).entries) {
      stdout.writeln('${entry.key}=${entry.value}');
    }
  } finally {
    await app.close();
  }
}
