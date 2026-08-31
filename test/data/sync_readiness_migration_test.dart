import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/sync/sqlite_sync_readiness.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test(
    'v12 identities survive v13 migration and deletes become tombstones',
    () async {
      sqfliteFfiInit();
      final directory = await Directory.systemTemp.createTemp('jax-sync-v13-');
      final path = '${directory.path}/jax.db';
      final old = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 12,
          onCreate: (db, _) async {
            await db.execute('''CREATE TABLE categories (
            id TEXT PRIMARY KEY, name TEXT, sort_order INTEGER, color_key INTEGER,
            created_at_utc INTEGER, updated_at_utc INTEGER)''');
            await db.execute('''CREATE TABLE events (
            id TEXT PRIMARY KEY, name TEXT, status TEXT, parent_event_id TEXT,
            sort_order INTEGER, category_id TEXT, first_started_at_utc INTEGER,
            completed_at_utc INTEGER, created_at_utc INTEGER,
            updated_at_utc INTEGER)''');
            await db.execute('''CREATE TABLE run_segments (
            id TEXT PRIMARY KEY, event_id TEXT, started_at_utc INTEGER,
            ended_at_utc INTEGER, created_at_utc INTEGER)''');
            await db.execute('''CREATE TABLE routine_categories (
            id TEXT PRIMARY KEY, name TEXT, sort_order INTEGER, color_key INTEGER,
            created_at_utc INTEGER, updated_at_utc INTEGER)''');
            await db.execute('''CREATE TABLE routines (
            id TEXT PRIMARY KEY, name TEXT, routine_category_id TEXT,
            routine_type TEXT, recurrence_type TEXT, weekday_mask INTEGER,
            is_active INTEGER, sort_order INTEGER, created_at_utc INTEGER,
            updated_at_utc INTEGER)''');
            await db.execute('''CREATE TABLE routine_executions (
            id TEXT PRIMARY KEY, routine_id TEXT, occurrence_date TEXT,
            status TEXT, completed_at_utc INTEGER, created_at_utc INTEGER,
            updated_at_utc INTEGER)''');
            await db.execute('''CREATE TABLE routine_run_segments (
            id TEXT PRIMARY KEY, routine_execution_id TEXT,
            started_at_utc INTEGER, ended_at_utc INTEGER,
            created_at_utc INTEGER)''');
            await db.execute('''CREATE TABLE event_day_plans (
            event_id TEXT, day_date TEXT, order_index INTEGER,
            created_at_utc INTEGER, PRIMARY KEY(event_id, day_date))''');
            await db.execute(
              '''CREATE TABLE world_category_collapse_preferences (
            section_key TEXT PRIMARY KEY)''',
            );
            await db.insert('categories', {
              'id': 'category-uuid',
              'name': 'C',
              'sort_order': 0,
              'color_key': 0,
              'created_at_utc': 10,
              'updated_at_utc': 10,
            });
            await db.insert('events', {
              'id': 'event-uuid',
              'name': 'E',
              'status': 'completed',
              'sort_order': 0,
              'category_id': 'category-uuid',
              'created_at_utc': 20,
              'updated_at_utc': 20,
            });
            await db.insert('run_segments', {
              'id': 'segment-uuid',
              'event_id': 'event-uuid',
              'started_at_utc': 21,
              'ended_at_utc': 22,
              'created_at_utc': 21,
            });
            await db.insert('event_day_plans', {
              'event_id': 'event-uuid',
              'day_date': '2026-08-30',
              'order_index': 0,
              'created_at_utc': 20,
            });
          },
        ),
      );
      await old.close();

      var app = await AppDatabase.open(path);
      expect((await app.database.query('events')).single['id'], 'event-uuid');
      expect(
        (await app.database.query('run_segments')).single['updated_at_utc'],
        21,
      );
      expect(
        (await app.database.query('event_day_plans')).single['updated_at_utc'],
        20,
      );
      await app.database.delete(
        'event_day_plans',
        where: 'event_id = ? AND day_date = ?',
        whereArgs: ['event-uuid', '2026-08-30'],
      );
      await app.database.delete(
        'run_segments',
        where: 'id = ?',
        whereArgs: ['segment-uuid'],
      );
      final tombstones = await app.database.query(
        'sync_tombstones',
        orderBy: 'entity_type',
      );
      expect(
        tombstones.map((row) => row['entity_id']),
        containsAll(['event-uuid@2026-08-30', 'segment-uuid']),
      );
      await app.close();

      app = await AppDatabase.open(path);
      expect(await app.database.query('sync_tombstones'), hasLength(2));
      expect(await SqliteSyncReadiness(app).validate(), isEmpty);
      expect(
        (await app.database.rawQuery('PRAGMA user_version'))
            .single['user_version'],
        14,
      );
      await app.close();
      await directory.delete(recursive: true);
    },
  );

  test(
    'readiness audit reports global running and category violations',
    () async {
      final app = await AppDatabase.inMemory();
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      await app.database.insert('events', {
        'id': 'parent',
        'name': 'P',
        'status': 'running',
        'sort_order': 0,
        'created_at_utc': now,
        'updated_at_utc': now,
      });
      await app.database.insert('events', {
        'id': 'child',
        'name': 'C',
        'status': 'pending',
        'parent_event_id': 'parent',
        'category_id': null,
        'sort_order': 0,
        'created_at_utc': now,
        'updated_at_utc': now,
      });
      final issues = await SqliteSyncReadiness(app).validate();
      expect(
        issues.map((issue) => issue.code),
        contains('event-running-segment'),
      );
      await app.close();
    },
  );

  test(
    'database metadata triggers cover updates and cascading deletes',
    () async {
      final app = await AppDatabase.inMemory();
      const created = 1000;
      await app.database.insert('events', {
        'id': 'event-uuid',
        'name': 'before',
        'status': 'completed',
        'sort_order': 0,
        'created_at_utc': created,
        'updated_at_utc': created,
      });
      await app.database.insert('run_segments', {
        'id': 'segment-uuid',
        'event_id': 'event-uuid',
        'started_at_utc': 1000,
        'ended_at_utc': 2000,
        'created_at_utc': 1000,
      });
      await app.database.update(
        'events',
        {'name': 'after'},
        where: 'id = ?',
        whereArgs: ['event-uuid'],
      );
      final event = (await app.database.query('events')).single;
      expect(event['id'], 'event-uuid');
      expect(event['updated_at_utc'] as int, greaterThan(created));

      await app.database.delete(
        'events',
        where: 'id = ?',
        whereArgs: ['event-uuid'],
      );
      final tombstones = await app.database.query('sync_tombstones');
      expect(
        tombstones.map((row) => '${row['entity_type']}:${row['entity_id']}'),
        containsAll(['event:event-uuid', 'eventRunSegment:segment-uuid']),
      );
      await app.close();
    },
  );
}
