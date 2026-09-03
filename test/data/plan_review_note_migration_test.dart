import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jax/data/database/app_database.dart';

void main() {
  test(
    'v16 to v17 adds empty review notes without mutating business facts',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'jax-review-v17-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}${Platform.pathSeparator}jax.db';
      var app = await AppDatabase.open(path);
      final db = app.database;
      await db.insert('world_nodes', {
        'id': '11111111-1111-4111-8111-111111111111',
        'name': 'Node',
        'status': 'inProgress',
        'parent_world_node_id': null,
        'category_id': null,
        'sort_order': 0,
        'created_at_utc': 1,
        'updated_at_utc': 1,
      });
      await db.insert('plans', {
        'id': 'plan',
        'world_node_id': '11111111-1111-4111-8111-111111111111',
        'title': null,
        'status': 'focused',
        'round_number': 1,
        'ended_at_utc': null,
        'created_at_utc': 2,
        'updated_at_utc': 2,
      });
      await db.insert('plan_items', {
        'id': 'item',
        'plan_id': 'plan',
        'title': 'Step',
        'note': null,
        'status': 'draft',
        'sort_order': 0,
        'created_at_utc': 3,
        'updated_at_utc': 3,
      });
      final before = await _facts(db);
      await db.execute('DROP TABLE plan_review_notes');
      await db.execute('PRAGMA user_version = 16');
      await app.close();

      app = await AppDatabase.open(path);
      addTearDown(app.close);
      expect(
        (await app.database.rawQuery('PRAGMA user_version'))
            .single
            .values
            .single,
        17,
      );
      expect(await app.database.query('plan_review_notes'), isEmpty);
      expect(await _facts(app.database), before);
      expect(await app.database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      expect(
        await app.database.query(
          'sqlite_master',
          where: 'type = ? AND name = ?',
          whereArgs: ['trigger', 'plan_review_notes_sync_delete'],
        ),
        hasLength(1),
      );
    },
  );
}

Future<Map<String, List<Map<String, Object?>>>> _facts(dynamic db) async {
  final result = <String, List<Map<String, Object?>>>{};
  for (final table in const [
    'world_nodes',
    'plans',
    'plan_items',
    'events',
    'event_day_plans',
    'run_segments',
    'routine_executions',
    'routine_run_segments',
  ]) {
    result[table] = await db.query(table);
  }
  return result;
}
