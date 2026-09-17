import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jax/data/database/app_database.dart';

void main() {
  test(
    'v17 to v18 moves Plan attention to WorldNode without changing facts',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'jax-attention-v18-',
      );
      final path = '${directory.path}${Platform.pathSeparator}jax.db';
      AppDatabase? app;
      addTearDown(() async {
        await app?.close();
        await directory.delete(recursive: true);
      });
      app = await AppDatabase.open(path);
      final db = app.database;

      await db.execute('DROP TABLE run_segments');
      await db.execute('DROP TABLE event_day_plans');
      await db.execute('DROP TABLE events');
      await db.execute('DROP TABLE plan_review_notes');
      await db.execute('DROP TABLE plan_items');
      await db.execute('DROP TABLE plans');
      await db.execute('''CREATE TABLE plans (
      id TEXT PRIMARY KEY,
      world_node_id TEXT NOT NULL REFERENCES world_nodes(id) ON DELETE RESTRICT,
      title TEXT,
      status TEXT NOT NULL CHECK(status IN ('focused','waiting','ended')),
      round_number INTEGER NOT NULL,
      ended_at_utc INTEGER,
      created_at_utc INTEGER NOT NULL,
      updated_at_utc INTEGER NOT NULL,
      UNIQUE(world_node_id, round_number)
    )''');
      await db.execute('''CREATE TABLE plan_items (
      id TEXT PRIMARY KEY,
      plan_id TEXT NOT NULL REFERENCES plans(id) ON DELETE RESTRICT,
      title TEXT NOT NULL,
      note TEXT,
      status TEXT NOT NULL,
      sort_order INTEGER NOT NULL,
      created_at_utc INTEGER NOT NULL,
      updated_at_utc INTEGER NOT NULL
    )''');
      await db.execute('''CREATE TABLE plan_review_notes (
      id TEXT PRIMARY KEY,
      plan_id TEXT NOT NULL REFERENCES plans(id) ON DELETE RESTRICT,
      content TEXT NOT NULL,
      created_at_utc INTEGER NOT NULL,
      updated_at_utc INTEGER NOT NULL
    )''');
      await db.execute('''CREATE TABLE events (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      status TEXT NOT NULL,
      source_plan_item_id TEXT UNIQUE REFERENCES plan_items(id) ON DELETE RESTRICT,
      category_id TEXT REFERENCES categories(id) ON DELETE SET NULL,
      first_started_at_utc INTEGER,
      completed_at_utc INTEGER,
      created_at_utc INTEGER NOT NULL,
      updated_at_utc INTEGER NOT NULL
    )''');
      await db.execute('''CREATE TABLE run_segments (
      id TEXT PRIMARY KEY,
      event_id TEXT NOT NULL REFERENCES events(id) ON DELETE CASCADE,
      started_at_utc INTEGER NOT NULL,
      ended_at_utc INTEGER,
      created_at_utc INTEGER NOT NULL,
      updated_at_utc INTEGER NOT NULL DEFAULT 0
    )''');
      await db.execute('''CREATE TABLE event_day_plans (
      event_id TEXT NOT NULL REFERENCES events(id) ON DELETE CASCADE,
      day_date TEXT NOT NULL,
      order_index INTEGER NOT NULL,
      created_at_utc INTEGER NOT NULL,
      updated_at_utc INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY(event_id, day_date)
    )''');

      for (final value in const [
        ('11111111-1111-4111-8111-111111111111', 'Focused'),
        ('22222222-2222-4222-8222-222222222222', 'Waiting'),
        ('33333333-3333-4333-8333-333333333333', 'Ended'),
      ]) {
        await db.insert('world_nodes', {
          'id': value.$1,
          'name': value.$2,
          'status': 'inProgress',
          'is_focused': 0,
          'parent_world_node_id': null,
          'category_id': null,
          'sort_order': 0,
          'created_at_utc': 1,
          'updated_at_utc': 1,
        });
      }
      await db.insert('plans', {
        'id': 'focused-plan',
        'world_node_id': '11111111-1111-4111-8111-111111111111',
        'title': null,
        'status': 'focused',
        'round_number': 1,
        'ended_at_utc': null,
        'created_at_utc': 2,
        'updated_at_utc': 2,
      });
      await db.insert('plans', {
        'id': 'waiting-plan',
        'world_node_id': '22222222-2222-4222-8222-222222222222',
        'title': null,
        'status': 'waiting',
        'round_number': 1,
        'ended_at_utc': null,
        'created_at_utc': 2,
        'updated_at_utc': 2,
      });
      await db.insert('plans', {
        'id': 'ended-plan',
        'world_node_id': '33333333-3333-4333-8333-333333333333',
        'title': null,
        'status': 'ended',
        'round_number': 1,
        'ended_at_utc': 5,
        'created_at_utc': 2,
        'updated_at_utc': 5,
      });
      await db.insert('plan_items', {
        'id': 'item',
        'plan_id': 'focused-plan',
        'title': 'Step',
        'note': null,
        'status': 'next',
        'sort_order': 0,
        'created_at_utc': 3,
        'updated_at_utc': 3,
      });
      await db.insert('plan_review_notes', {
        'id': '44444444-4444-4444-8444-444444444444',
        'plan_id': 'focused-plan',
        'content': 'Keep review',
        'created_at_utc': 4,
        'updated_at_utc': 4,
      });
      final itemBefore = await db.query('plan_items');
      final noteBefore = await db.query('plan_review_notes');
      final generationBefore = await db.query('dataset_metadata');
      await db.execute('PRAGMA user_version = 17');
      await app.close();
      app = null;

      app = await AppDatabase.open(path);
      expect(
        (await app.database.rawQuery('PRAGMA user_version'))
            .single
            .values
            .single,
        AppDatabase.schemaVersion,
      );
      expect(
        await app.database.query('jax_day_carry_over_initializations'),
        isEmpty,
      );
      final nodes = await app.database.query('world_nodes', orderBy: 'id');
      expect(nodes.map((row) => row['is_focused']), [1, 0, 0]);
      final plans = await app.database.query('plans', orderBy: 'id');
      expect(plans.map((row) => row['status']), [
        'ended',
        'current',
        'current',
      ]);
      expect(await app.database.query('plan_items'), [
        for (final item in itemBefore)
          {...item, 'promoted_world_node_id': null},
      ]);
      expect(await app.database.query('plan_review_notes'), noteBefore);
      expect(await app.database.query('dataset_metadata'), generationBefore);
      expect(await app.database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );
}
