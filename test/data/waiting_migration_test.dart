import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('v4 to v5 preserves hierarchy, order and run segments', () async {
    sqfliteFfiInit();
    final directory = await Directory.systemTemp.createTemp('jax-v4-v5-');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}${Platform.pathSeparator}jax.db';
    final old = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 4,
        onCreate: (db, _) async {
          await db.execute('''CREATE TABLE events (
          id TEXT PRIMARY KEY, name TEXT NOT NULL,
          status TEXT NOT NULL CHECK(status IN ('pending','running','paused','completed')),
          parent_event_id TEXT REFERENCES events(id) ON DELETE RESTRICT,
          sort_order INTEGER, first_started_at_utc INTEGER,
          completed_at_utc INTEGER, created_at_utc INTEGER NOT NULL,
          updated_at_utc INTEGER NOT NULL)''');
          await db.execute('''CREATE TABLE run_segments (
          id TEXT PRIMARY KEY,
          event_id TEXT NOT NULL REFERENCES events(id) ON DELETE CASCADE,
          started_at_utc INTEGER NOT NULL, ended_at_utc INTEGER,
          created_at_utc INTEGER NOT NULL)''');
        },
      ),
    );
    final time = DateTime.utc(2026).millisecondsSinceEpoch;
    await old.insert('events', {
      'id': 'p',
      'name': 'parent',
      'status': 'paused',
      'sort_order': 2,
      'created_at_utc': time,
      'updated_at_utc': time,
    });
    await old.insert('events', {
      'id': 'c',
      'name': 'child',
      'status': 'paused',
      'parent_event_id': 'p',
      'sort_order': 4,
      'first_started_at_utc': time,
      'created_at_utc': time,
      'updated_at_utc': time,
    });
    await old.insert('run_segments', {
      'id': 's',
      'event_id': 'c',
      'started_at_utc': time,
      'ended_at_utc': time + 60000,
      'created_at_utc': time,
    });
    await old.close();

    final upgraded = await AppDatabase.open(path);
    addTearDown(upgraded.close);
    final repository = SqliteEventRepository(upgraded);
    final columns = await upgraded.database.rawQuery(
      'PRAGMA table_info(events)',
    );
    expect(columns.map((row) => row['name']), contains('category_id'));
    final child = await repository.getEvent('c');
    expect(child!.parentEventId, 'p');
    expect(child.sortOrder, 4);
    expect(await repository.getRunSegments('c'), hasLength(1));
    await repository.updateEvent(child.copyWith(status: EventStatus.waiting));
    expect((await repository.getEvent('c'))!.status, EventStatus.waiting);
    final version = await upgraded.database.rawQuery('PRAGMA user_version');
    expect(version.single['user_version'], 8);
  });
}
