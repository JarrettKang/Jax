import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('v2 database migrates to v3 without changing existing facts', () async {
    sqfliteFfiInit();
    final directory = await Directory.systemTemp.createTemp('jax-v2-v3-');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}${Platform.pathSeparator}jax.db';
    final started = DateTime.utc(2026, 8, 24, 8);
    final ended = started.add(const Duration(hours: 2));

    final old = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (database, _) async {
          await database.execute('''CREATE TABLE events (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL CHECK(length(trim(name)) > 0),
            status TEXT NOT NULL CHECK(status IN ('pending','running','paused','completed')),
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
    await old.insert('events', {
      'id': 'existing',
      'name': '旧记录',
      'status': 'completed',
      'first_started_at_utc': started.millisecondsSinceEpoch,
      'completed_at_utc': ended.millisecondsSinceEpoch,
      'created_at_utc': started.millisecondsSinceEpoch,
      'updated_at_utc': ended.millisecondsSinceEpoch,
    });
    await old.insert('run_segments', {
      'id': 'segment',
      'event_id': 'existing',
      'started_at_utc': started.millisecondsSinceEpoch,
      'ended_at_utc': ended.millisecondsSinceEpoch,
      'created_at_utc': started.millisecondsSinceEpoch,
    });
    await old.close();

    final upgraded = await AppDatabase.open(path);
    addTearDown(upgraded.close);
    final repository = SqliteEventRepository(upgraded);
    final event = await repository.getEvent('existing');
    final segments = await repository.getRunSegments('existing');

    expect(AppDatabase.schemaVersion, 3);
    expect(event?.parentEventId, isNull);
    expect(event?.status.name, 'completed');
    expect(event?.firstStartedAt, started);
    expect(event?.completedAt, ended);
    expect(segments.single.startedAt, started);
    expect(segments.single.endedAt, ended);
    final columns = await upgraded.database.rawQuery(
      'PRAGMA table_info(events)',
    );
    expect(columns.map((row) => row['name']), contains('parent_event_id'));
  });
}
