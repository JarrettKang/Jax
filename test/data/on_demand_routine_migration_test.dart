import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test(
    'v11 routines migrate as scheduled and executions allow same-day repeats',
    () async {
      sqfliteFfiInit();
      final directory = await Directory.systemTemp.createTemp(
        'jax-on-demand-migration-',
      );
      final path = '${directory.path}/jax.db';
      final old = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 11,
          onCreate: (database, _) async {
            await database.execute(
              'CREATE TABLE routine_categories (id TEXT PRIMARY KEY)',
            );
            await database.execute(
              '''CREATE TABLE routines (
            id TEXT PRIMARY KEY, name TEXT NOT NULL, routine_category_id TEXT,
            recurrence_type TEXT NOT NULL, weekday_mask INTEGER NOT NULL,
            is_active INTEGER NOT NULL, sort_order INTEGER NOT NULL,
            created_at_utc INTEGER NOT NULL, updated_at_utc INTEGER NOT NULL)''',
            );
            await database.execute('''CREATE TABLE routine_executions (
            id TEXT PRIMARY KEY, routine_id TEXT NOT NULL,
            occurrence_date TEXT NOT NULL, status TEXT NOT NULL,
            completed_at_utc INTEGER, created_at_utc INTEGER NOT NULL,
            updated_at_utc INTEGER NOT NULL,
            UNIQUE(routine_id, occurrence_date))''');
            await database.execute('''CREATE TABLE routine_run_segments (
            id TEXT PRIMARY KEY, routine_execution_id TEXT NOT NULL,
            started_at_utc INTEGER NOT NULL, ended_at_utc INTEGER,
            created_at_utc INTEGER NOT NULL)''');
            await database.insert('routines', {
              'id': 'routine',
              'name': '既有日常',
              'recurrence_type': 'daily',
              'weekday_mask': 0,
              'is_active': 1,
              'sort_order': 0,
              'created_at_utc': 1,
              'updated_at_utc': 1,
            });
            await database.insert('routine_executions', {
              'id': 'execution-1',
              'routine_id': 'routine',
              'occurrence_date': '2026-08-29',
              'status': 'completed',
              'created_at_utc': 1,
              'updated_at_utc': 2,
            });
            await database.insert('routine_run_segments', {
              'id': 'segment',
              'routine_execution_id': 'execution-1',
              'started_at_utc': 1,
              'ended_at_utc': 2,
              'created_at_utc': 1,
            });
          },
        ),
      );
      await old.close();

      final app = await AppDatabase.open(path);
      expect(
        (await app.database.query('routines')).single['routine_type'],
        'scheduled',
      );
      await app.database.insert('routine_executions', {
        'id': 'execution-2',
        'routine_id': 'routine',
        'occurrence_date': '2026-08-29',
        'status': 'completed',
        'created_at_utc': 3,
        'updated_at_utc': 4,
      });
      expect(await app.database.query('routine_executions'), hasLength(2));
      expect(
        (await app.database.query('routine_run_segments')).single['id'],
        'segment',
      );
      expect(
        (await app.database.rawQuery('PRAGMA user_version'))
            .single['user_version'],
        AppDatabase.schemaVersion,
      );
      await app.close();
      await directory.delete(recursive: true);
    },
  );
}
