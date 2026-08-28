import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('v10 categories receive deterministic valid palette keys', () async {
    sqfliteFfiInit();
    final dir = await Directory.systemTemp.createTemp('jax-color-migration-');
    final path = '${dir.path}/jax.db';
    final old = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 10,
        onCreate: (db, _) async {
          for (final table in ['categories', 'routine_categories']) {
            await db.execute(
              'CREATE TABLE $table (id TEXT PRIMARY KEY, name TEXT NOT NULL UNIQUE, sort_order INTEGER NOT NULL, created_at_utc INTEGER NOT NULL, updated_at_utc INTEGER NOT NULL)',
            );
          }
          await db.insert('categories', {
            'id': 'w2',
            'name': '二',
            'sort_order': 1,
            'created_at_utc': 1,
            'updated_at_utc': 1,
          });
          await db.insert('categories', {
            'id': 'w1',
            'name': '一',
            'sort_order': 0,
            'created_at_utc': 1,
            'updated_at_utc': 1,
          });
          await db.insert('routine_categories', {
            'id': 'r1',
            'name': '日常',
            'sort_order': 0,
            'created_at_utc': 1,
            'updated_at_utc': 1,
          });
        },
      ),
    );
    await old.close();

    final app = await AppDatabase.open(path);
    final world = await app.database.query('categories', orderBy: 'sort_order');
    final routines = await app.database.query('routine_categories');
    expect(world.map((row) => row['color_key']), [0, 1]);
    expect(routines.single['color_key'], 2);
    expect(world.map((row) => row['name']), ['一', '二']);
    await app.close();
    await dir.delete(recursive: true);
  });
}
