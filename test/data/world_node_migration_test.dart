import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/world_node_ids.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/database/world_node_migration_report.dart';
import 'package:jax/data/database/world_node_shadow_migration.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'v13 shadow migration preserves Event facts and copies structure exactly',
    () async {
      final fixture = await _v13Fixture();
      addTearDown(fixture.dispose);
      final before = await _legacyFacts(fixture.path);

      final app = await AppDatabase.open(fixture.path);
      addTearDown(app.close);
      expect(
        (await app.database.rawQuery('PRAGMA user_version'))
            .single['user_version'],
        14,
      );
      final report = await WorldNodeMigrationReporter(app.database).inspect();
      expect(report.toJson(), containsPair('legacyEvents', 5));
      expect(report.toJson(), containsPair('worldNodes', 5));
      expect(report.isExactMigration, isTrue);

      final nodes = await app.database.query('world_nodes');
      final byName = {for (final row in nodes) row['name']: row};
      expect(byName['A']!['status'], 'completed');
      for (final name in ['B', 'C', 'D', 'E']) {
        expect(byName[name]!['status'], 'inProgress');
      }
      expect(
        byName['C']!['parent_world_node_id'],
        WorldNodeIds.fromLegacyEvent('b'),
      );
      expect(byName['D']!['sort_order'], 0);
      expect(byName['C']!['sort_order'], 1);
      expect(byName['C']!['category_id'], isNull);
      expect(byName['B']!['category_id'], 'category-2');

      final after = await _legacyFactsFromDatabase(app.database);
      expect(after, before);
      expect(
        (await app.database.query('run_segments')).single,
        containsPair('event_id', 'e'),
      );
      expect(
        (await app.database.query('run_segments')).single['ended_at_utc'],
        isNull,
      );
      expect(await app.database.query('event_day_plans'), hasLength(4));
    },
  );

  test('deterministic ids and migration reruns are stable', () async {
    expect(
      WorldNodeIds.fromLegacyEvent('same-event'),
      WorldNodeIds.fromLegacyEvent('same-event'),
    );
    expect(
      WorldNodeIds.fromLegacyEvent('same-event'),
      isNot(WorldNodeIds.fromLegacyEvent('different-event')),
    );
    final first = await _v13Fixture();
    final second = await _v13Fixture();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    final firstApp = await AppDatabase.open(first.path);
    final secondApp = await AppDatabase.open(second.path);
    addTearDown(firstApp.close);
    addTearDown(secondApp.close);
    final firstIds = (await firstApp.database.query(
      'world_nodes',
      columns: ['id'],
      orderBy: 'id',
    )).map((row) => row['id']).toList();
    final secondIds = (await secondApp.database.query(
      'world_nodes',
      columns: ['id'],
      orderBy: 'id',
    )).map((row) => row['id']).toList();
    expect(secondIds, firstIds);

    final linksBefore = await firstApp.database.query(
      'legacy_event_world_node_links',
      orderBy: 'id',
    );
    await WorldNodeShadowMigration.run(firstApp.database);
    expect(await firstApp.database.query('world_nodes'), hasLength(5));
    expect(
      await firstApp.database.query(
        'legacy_event_world_node_links',
        orderBy: 'id',
      ),
      linksBefore,
    );
  });

  test(
    'deep hierarchy, sibling order, and root category copy exactly',
    () async {
      final app = await AppDatabase.inMemory();
      addTearDown(app.close);
      await app.database.insert('categories', {
        'id': 'category',
        'name': '科研',
        'sort_order': 0,
        'color_key': 0,
        'created_at_utc': 1,
        'updated_at_utc': 1,
      });
      final events = [
        ('a', 'A', null, 0, 'category'),
        ('b', 'B', 'a', 1, null),
        ('e', 'E', 'a', 0, null),
        ('c', 'C', 'b', 1, null),
        ('d', 'D', 'b', 0, null),
      ];
      for (var index = 0; index < events.length; index++) {
        final event = events[index];
        await app.database.insert('events', {
          'id': event.$1,
          'name': event.$2,
          'status': 'paused',
          'parent_event_id': event.$3,
          'sort_order': event.$4,
          'category_id': event.$5,
          'created_at_utc': 10 + index,
          'updated_at_utc': 10 + index,
        });
      }
      await WorldNodeShadowMigration.run(app.database);
      final nodes = {
        for (final row in await app.database.query('world_nodes'))
          row['id']! as String: row,
      };
      Map<String, Object?> node(String legacyId) =>
          nodes[WorldNodeIds.fromLegacyEvent(legacyId)]!;
      expect(node('b')['parent_world_node_id'], node('a')['id']);
      expect(node('c')['parent_world_node_id'], node('b')['id']);
      expect(node('d')['parent_world_node_id'], node('b')['id']);
      expect(node('e')['parent_world_node_id'], node('a')['id']);
      expect(node('e')['sort_order'], 0);
      expect(node('b')['sort_order'], 1);
      expect(node('d')['sort_order'], 0);
      expect(node('c')['sort_order'], 1);
      expect(node('a')['category_id'], 'category');
      for (final legacyId in ['b', 'c', 'd', 'e']) {
        expect(node(legacyId)['category_id'], isNull);
      }
    },
  );

  test('injected shadow migration failure rolls back every new row', () async {
    final app = await AppDatabase.inMemory();
    addTearDown(app.close);
    await app.database.delete('legacy_event_world_node_links');
    await app.database.delete('world_nodes');
    for (var index = 0; index < 3; index++) {
      await app.database.insert('events', {
        'id': 'rollback-$index',
        'name': 'Rollback $index',
        'status': 'pending',
        'sort_order': index,
        'created_at_utc': 100 + index,
        'updated_at_utc': 100 + index,
      });
    }
    await expectLater(
      WorldNodeShadowMigration.run(app.database, failAfterInsert: 2),
      throwsStateError,
    );
    expect(await app.database.query('world_nodes'), isEmpty);
    expect(await app.database.query('legacy_event_world_node_links'), isEmpty);
    expect(await app.database.query('events'), hasLength(3));
  });
}

class _Fixture {
  const _Fixture(this.directory, this.path);
  final Directory directory;
  final String path;
  Future<void> dispose() => directory.delete(recursive: true);
}

Future<_Fixture> _v13Fixture() async {
  final directory = await Directory.systemTemp.createTemp('jax-world-v13-');
  final path = '${directory.path}${Platform.pathSeparator}jax.db';
  final database = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 13,
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
          ended_at_utc INTEGER, created_at_utc INTEGER,
          updated_at_utc INTEGER)''');
        await db.execute('''CREATE TABLE event_day_plans (
          event_id TEXT, day_date TEXT, order_index INTEGER,
          created_at_utc INTEGER, updated_at_utc INTEGER,
          PRIMARY KEY(event_id, day_date))''');
        await db.execute('''CREATE TABLE sync_tombstones (
          entity_type TEXT, entity_id TEXT, deleted_at_utc INTEGER,
          PRIMARY KEY(entity_type, entity_id))''');
        for (var index = 1; index <= 2; index++) {
          await db.insert('categories', {
            'id': 'category-$index',
            'name': 'Category $index',
            'sort_order': index - 1,
            'color_key': index,
            'created_at_utc': index,
            'updated_at_utc': index,
          });
        }
        final events = [
          ('a', 'A', 'completed', null, 4, 'category-1'),
          ('b', 'B', 'pending', null, 8, 'category-2'),
          ('c', 'C', 'paused', 'b', 5, null),
          ('d', 'D', 'waiting', 'b', 2, null),
          ('e', 'E', 'running', null, 12, null),
        ];
        for (var index = 0; index < events.length; index++) {
          final event = events[index];
          await db.insert('events', {
            'id': event.$1,
            'name': event.$2,
            'status': event.$3,
            'parent_event_id': event.$4,
            'sort_order': event.$5,
            'category_id': event.$6,
            'first_started_at_utc': event.$3 == 'pending' ? null : 100,
            'completed_at_utc': event.$3 == 'completed' ? 200 : null,
            'created_at_utc': 10 + index,
            'updated_at_utc': 20 + index,
          });
        }
        await db.insert('run_segments', {
          'id': 'open-e',
          'event_id': 'e',
          'started_at_utc': 150,
          'ended_at_utc': null,
          'created_at_utc': 150,
          'updated_at_utc': 150,
        });
        for (var index = 0; index < 4; index++) {
          await db.insert('event_day_plans', {
            'event_id': ['b', 'c', 'd', 'e'][index],
            'day_date': '2026-08-31',
            'order_index': index,
            'created_at_utc': 30 + index,
            'updated_at_utc': 30 + index,
          });
        }
      },
    ),
  );
  await database.close();
  return _Fixture(directory, path);
}

Future<Map<String, List<Map<String, Object?>>>> _legacyFacts(
  String path,
) async {
  final database = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(readOnly: true),
  );
  try {
    return await _legacyFactsFromDatabase(database);
  } finally {
    await database.close();
  }
}

Future<Map<String, List<Map<String, Object?>>>> _legacyFactsFromDatabase(
  Database database,
) async => {
  for (final table in ['events', 'run_segments', 'event_day_plans'])
    table: await database.query(table, orderBy: 'rowid'),
};
