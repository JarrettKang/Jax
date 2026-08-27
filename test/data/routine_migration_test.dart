import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('v6 data migrates to v7 with Routine tables intact', () async {
    sqfliteFfiInit();
    final dir = await Directory.systemTemp.createTemp('jax-routine-migration-');
    final path = '${dir.path}/jax.db';
    final old = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 6,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE categories (id TEXT PRIMARY KEY,name TEXT NOT NULL UNIQUE,sort_order INTEGER NOT NULL,created_at_utc INTEGER NOT NULL,updated_at_utc INTEGER NOT NULL)',
          );
          await db.execute(
            "CREATE TABLE events (id TEXT PRIMARY KEY,name TEXT NOT NULL,status TEXT NOT NULL,parent_event_id TEXT,sort_order INTEGER,category_id TEXT,first_started_at_utc INTEGER,completed_at_utc INTEGER,created_at_utc INTEGER NOT NULL,updated_at_utc INTEGER NOT NULL)",
          );
          await db.execute(
            'CREATE TABLE run_segments (id TEXT PRIMARY KEY,event_id TEXT NOT NULL,started_at_utc INTEGER NOT NULL,ended_at_utc INTEGER,created_at_utc INTEGER NOT NULL)',
          );
          await db.insert('events', {
            'id': 'old',
            'name': '旧事件',
            'status': 'paused',
            'sort_order': 0,
            'created_at_utc': 1,
            'updated_at_utc': 1,
          });
        },
      ),
    );
    await old.close();
    final app = await AppDatabase.open(path);
    expect((await app.database.query('events')).single['name'], '旧事件');
    final tables = await app.database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    );
    expect(
      tables.map((r) => r['name']),
      containsAll(['routines', 'routine_executions', 'routine_run_segments']),
    );
    expect(
      (await app.database.rawQuery('PRAGMA user_version'))
          .single['user_version'],
      7,
    );
    await app.close();
    await dir.delete(recursive: true);
  });
}
