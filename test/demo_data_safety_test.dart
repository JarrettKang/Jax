import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:path/path.dart' as p;

import '../tool/demo_data.dart';

void main() {
  test(
    'requires an explicit isolated .db, refuses escapes and real-data paths',
    () {
      for (final name in [
        '',
        'jax.db',
        'docs/demo.db',
        '.local_private/demo/../../jax.db',
        '.local_private/demo/example.txt',
      ]) {
        expect(() => validateDemoOutput(name), throwsA(anything));
      }
      final appData = Platform.environment['APPDATA'];
      if (appData != null) {
        expect(
          () => validateDemoOutput(p.join(appData, 'Jax', 'jax.db')),
          throwsA(anything),
        );
      }
    },
  );
  test('existing targets and SQLite sidecars are preserved', () async {
    final dir = Directory(
      '.local_private/demo/test-${DateTime.now().microsecondsSinceEpoch}',
    );
    await dir.create(recursive: true);
    try {
      for (final suffix in ['', '-wal', '-shm', '-journal']) {
        final file = File(p.join(dir.path, 'fixture.db$suffix'));
        await file.writeAsString('sentinel');
        expect(
          () => validateDemoOutput(p.join(dir.path, 'fixture.db')),
          throwsStateError,
        );
        expect(await file.readAsString(), 'sentinel');
        await file.delete();
      }
    } finally {
      await dir.delete();
    }
  });
  test('fresh seeds have identical rows, valid foreign keys and cannot be reseeded', () async {
    final first = await AppDatabase.inMemory();
    // inMemory() uses a single-instance database; close before the second one.
    await seedDemo(first);
    final rows = await first.database.query('events', orderBy: 'id');
    expect(rows, hasLength(4));
    expect(await first.database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    await expectLater(seedDemo(first), throwsStateError);
    await first.close();
    final second = await AppDatabase.inMemory();
    try {
      await seedDemo(second);
      expect(await second.database.query('events', orderBy: 'id'), rows);
      expect(
        (await second.database.query('dataset_metadata')).single['generation'],
        'jax-synthetic-demo-v1',
      );
    } finally {
      await second.close();
    }
  });
}
