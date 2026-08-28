import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('v9 keeps World and Routine history while clearing old World category assignment', () async {
    sqfliteFfiInit();
    final dir = await Directory.systemTemp.createTemp(
      'jax-routine-category-v9-',
    );
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/jax.db';
    final old = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 9,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE categories (id TEXT PRIMARY KEY,name TEXT,sort_order INTEGER,created_at_utc INTEGER,updated_at_utc INTEGER)',
          );
          await db.execute(
            'CREATE TABLE events (id TEXT PRIMARY KEY,name TEXT,status TEXT,parent_event_id TEXT,sort_order INTEGER,category_id TEXT,first_started_at_utc INTEGER,completed_at_utc INTEGER,created_at_utc INTEGER,updated_at_utc INTEGER)',
          );
          await db.execute(
            'CREATE TABLE routines (id TEXT PRIMARY KEY,name TEXT,category_id TEXT,recurrence_type TEXT,weekday_mask INTEGER,is_active INTEGER,sort_order INTEGER,created_at_utc INTEGER,updated_at_utc INTEGER)',
          );
          await db.execute(
            'CREATE TABLE routine_executions (id TEXT PRIMARY KEY,routine_id TEXT,occurrence_date TEXT,status TEXT,completed_at_utc INTEGER,created_at_utc INTEGER,updated_at_utc INTEGER)',
          );
          await db.execute(
            'CREATE TABLE routine_run_segments (id TEXT PRIMARY KEY,routine_execution_id TEXT,started_at_utc INTEGER,ended_at_utc INTEGER,created_at_utc INTEGER)',
          );
          await db.insert('categories', {
            'id': 'world',
            'name': '科研',
            'sort_order': 0,
            'created_at_utc': 1,
            'updated_at_utc': 1,
          });
          await db.insert('events', {
            'id': 'event',
            'name': '课题',
            'status': 'paused',
            'sort_order': 0,
            'category_id': 'world',
            'created_at_utc': 1,
            'updated_at_utc': 1,
          });
          await db.insert('routines', {
            'id': 'routine',
            'name': '洗漱',
            'category_id': 'world',
            'recurrence_type': 'daily',
            'weekday_mask': 0,
            'is_active': 1,
            'sort_order': 0,
            'created_at_utc': 1,
            'updated_at_utc': 1,
          });
          await db.insert('routine_executions', {
            'id': 'execution',
            'routine_id': 'routine',
            'occurrence_date': '2026-08-27',
            'status': 'completed',
            'created_at_utc': 1,
            'updated_at_utc': 2,
          });
          await db.insert('routine_run_segments', {
            'id': 'segment',
            'routine_execution_id': 'execution',
            'started_at_utc': 1,
            'ended_at_utc': 2,
            'created_at_utc': 1,
          });
        },
      ),
    );
    await old.close();
    final app = await AppDatabase.open(path);
    expect((await app.database.query('categories')).single['name'], '科研');
    expect((await app.database.query('events')).single['category_id'], 'world');
    expect(
      (await app.database.query('routines')).single['routine_category_id'],
      isNull,
    );
    expect(await app.database.query('routine_executions'), hasLength(1));
    expect(await app.database.query('routine_run_segments'), hasLength(1));
    expect(await app.database.query('routine_categories'), isEmpty);
    await app.close();
  });
}
