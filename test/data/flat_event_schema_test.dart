import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('v15 hierarchy migrates to v16 flat standalone Events', () async {
    sqfliteFfiInit();
    final directory = await Directory.systemTemp.createTemp('jax-flat-v16-');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}${Platform.pathSeparator}jax.db';
    final old = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 15,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) async {
          await db.execute(
            '''CREATE TABLE categories (
            id TEXT PRIMARY KEY, name TEXT NOT NULL UNIQUE,
            sort_order INTEGER NOT NULL, color_key INTEGER NOT NULL,
            created_at_utc INTEGER NOT NULL, updated_at_utc INTEGER NOT NULL)''',
          );
          await db.execute(
            '''CREATE TABLE plan_items (
            id TEXT PRIMARY KEY, plan_id TEXT NOT NULL, title TEXT NOT NULL,
            note TEXT, status TEXT NOT NULL, sort_order INTEGER NOT NULL,
            created_at_utc INTEGER NOT NULL, updated_at_utc INTEGER NOT NULL)''',
          );
          await db.execute('''CREATE TABLE events (
            id TEXT PRIMARY KEY, name TEXT NOT NULL, status TEXT NOT NULL,
            parent_event_id TEXT REFERENCES events(id), sort_order INTEGER,
            category_id TEXT REFERENCES categories(id), first_started_at_utc INTEGER,
            completed_at_utc INTEGER, created_at_utc INTEGER NOT NULL,
            updated_at_utc INTEGER NOT NULL)''');
          await db.execute(
            '''CREATE TABLE run_segments (
            id TEXT PRIMARY KEY, event_id TEXT NOT NULL REFERENCES events(id),
            started_at_utc INTEGER NOT NULL, ended_at_utc INTEGER,
            created_at_utc INTEGER NOT NULL, updated_at_utc INTEGER NOT NULL)''',
          );
          await db.execute(
            '''CREATE TABLE event_day_plans (
            event_id TEXT NOT NULL REFERENCES events(id), day_date TEXT NOT NULL,
            order_index INTEGER NOT NULL, created_at_utc INTEGER NOT NULL,
            updated_at_utc INTEGER NOT NULL, PRIMARY KEY(event_id, day_date))''',
          );
          await db.execute('''CREATE TABLE sync_tombstones (
            entity_type TEXT NOT NULL, entity_id TEXT NOT NULL,
            deleted_at_utc INTEGER NOT NULL,
            PRIMARY KEY(entity_type, entity_id))''');
        },
      ),
    );
    await old.insert('categories', {
      'id': 'category',
      'name': '开发',
      'sort_order': 0,
      'color_key': 0,
      'created_at_utc': 1,
      'updated_at_utc': 1,
    });
    await old.insert('events', {
      'id': 'root',
      'name': 'Root',
      'status': 'paused',
      'parent_event_id': null,
      'sort_order': 0,
      'category_id': 'category',
      'created_at_utc': 1,
      'updated_at_utc': 1,
    });
    await old.insert('events', {
      'id': 'child',
      'name': 'Child',
      'status': 'pending',
      'parent_event_id': 'root',
      'sort_order': 0,
      'category_id': null,
      'created_at_utc': 2,
      'updated_at_utc': 2,
    });
    await old.close();

    final app = await AppDatabase.open(path);
    addTearDown(app.close);
    final columns = (await app.database.rawQuery('PRAGMA table_info(events)'))
        .map((row) => row['name'])
        .toSet();
    expect(columns, contains('source_plan_item_id'));
    expect(columns, isNot(contains('parent_event_id')));
    expect(columns, isNot(contains('sort_order')));
    expect(await app.database.query('events'), hasLength(2));
    final repository = SqliteEventRepository(app);
    expect(await repository.getEffectiveCategoryId('child'), 'category');
    expect((await repository.getEvent('child'))!.sourcePlanItemId, isNull);
    expect(await app.database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test(
    'planned source is unique and category is dynamically derived',
    () async {
      final app = await AppDatabase.inMemory();
      addTearDown(app.close);
      final db = app.database;
      await db.insert('categories', {
        'id': 'category',
        'name': '开发',
        'sort_order': 0,
        'color_key': 0,
        'created_at_utc': 1,
        'updated_at_utc': 1,
      });
      await db.insert('world_nodes', {
        'id': '11111111-1111-4111-8111-111111111111',
        'name': 'Root',
        'status': 'inProgress',
        'parent_world_node_id': null,
        'sort_order': 0,
        'category_id': 'category',
        'created_at_utc': 1,
        'updated_at_utc': 1,
      });
      await db.insert('world_nodes', {
        'id': '22222222-2222-4222-8222-222222222222',
        'name': 'Child',
        'status': 'inProgress',
        'parent_world_node_id': '11111111-1111-4111-8111-111111111111',
        'sort_order': 0,
        'category_id': null,
        'created_at_utc': 1,
        'updated_at_utc': 1,
      });
      await db.insert('plans', {
        'id': 'plan',
        'world_node_id': '22222222-2222-4222-8222-222222222222',
        'title': null,
        'status': 'current',
        'round_number': 1,
        'ended_at_utc': null,
        'created_at_utc': 1,
        'updated_at_utc': 1,
      });
      await db.insert('plan_items', {
        'id': 'item',
        'plan_id': 'plan',
        'title': 'Step',
        'note': null,
        'status': 'draft',
        'sort_order': 0,
        'created_at_utc': 1,
        'updated_at_utc': 1,
      });
      await db.insert('events', {
        'id': 'planned',
        'name': 'Planned',
        'status': 'pending',
        'source_plan_item_id': 'item',
        'category_id': null,
        'created_at_utc': 1,
        'updated_at_utc': 1,
      });
      final repository = SqliteEventRepository(app);
      expect(await repository.getEffectiveCategoryId('planned'), 'category');
      await expectLater(
        db.insert('events', {
          'id': 'duplicate',
          'name': 'Duplicate',
          'status': 'pending',
          'source_plan_item_id': 'item',
          'category_id': null,
          'created_at_utc': 1,
          'updated_at_utc': 1,
        }),
        throwsA(anything),
      );
      await expectLater(
        db.insert('events', {
          'id': 'invalid',
          'name': 'Invalid',
          'status': 'pending',
          'source_plan_item_id': 'item',
          'category_id': 'category',
          'created_at_utc': 1,
          'updated_at_utc': 1,
        }),
        throwsA(anything),
      );
    },
  );
}
