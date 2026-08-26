import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('v3 database migrates to v4 with stable sibling order', () async {
    sqfliteFfiInit();
    final directory = await Directory.systemTemp.createTemp('jax-v3-v4-');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}${Platform.pathSeparator}jax.db';
    final time = DateTime.utc(2026, 8, 25, 8);
    final old = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: (database, _) async {
          await database.execute('''CREATE TABLE events (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL CHECK(length(trim(name)) > 0),
            status TEXT NOT NULL CHECK(status IN ('pending','running','paused','completed')),
            parent_event_id TEXT REFERENCES events(id) ON DELETE RESTRICT,
            first_started_at_utc INTEGER,
            completed_at_utc INTEGER,
            created_at_utc INTEGER NOT NULL,
            updated_at_utc INTEGER NOT NULL
          )''');
          await database.execute('''CREATE TABLE run_segments (
            id TEXT PRIMARY KEY,
            event_id TEXT NOT NULL REFERENCES events(id) ON DELETE CASCADE,
            started_at_utc INTEGER NOT NULL,
            ended_at_utc INTEGER,
            created_at_utc INTEGER NOT NULL
          )''');
        },
      ),
    );
    Future<void> add(String id, String? parent, DateTime created) =>
        old.insert('events', {
          'id': id,
          'name': id,
          'status': 'pending',
          'parent_event_id': parent,
          'created_at_utc': created.millisecondsSinceEpoch,
          'updated_at_utc': created.millisecondsSinceEpoch,
        });
    await add('z-top', null, time);
    await add('a-top', null, time);
    await add('child-late', 'z-top', time.add(const Duration(minutes: 2)));
    await add('child-early', 'z-top', time.add(const Duration(minutes: 1)));
    await old.close();

    final upgraded = await AppDatabase.open(path);
    addTearDown(upgraded.close);
    final repository = SqliteEventRepository(upgraded);
    expect(
      (await repository.getOrderedTopLevelEvents()).map((event) => event.id),
      ['a-top', 'z-top'],
    );
    expect(
      (await repository.getDirectChildren('z-top')).map((event) => event.id),
      ['child-early', 'child-late'],
    );
    final version = await upgraded.database.rawQuery('PRAGMA user_version');
    expect(version.single['user_version'], 6);
  });
}
