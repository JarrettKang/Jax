import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/preferences/sqlite_world_category_collapse_store.dart';
import 'package:jax/core/preferences/world_category_collapse_store.dart';
import 'package:jax/data/sync/sqlite_sync_snapshot_adapter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('stores Category identities and the virtual unclassified key', () async {
    final database = await AppDatabase.inMemory();
    final store = SqliteWorldCategoryCollapseStore(database);

    expect(await store.loadCollapsedSectionKeys(), isEmpty);
    await store.setCollapsed('category:research', true);
    await store.setCollapsed(WorldCategoryCollapseStore.unclassifiedKey, true);
    expect(await store.loadCollapsedSectionKeys(), {
      'category:research',
      WorldCategoryCollapseStore.unclassifiedKey,
    });
    await store.setCollapsed('category:research', false);
    expect(await store.loadCollapsedSectionKeys(), {
      WorldCategoryCollapseStore.unclassifiedKey,
    });
    await database.close();
  });

  test(
    'collapsed sections survive reopening the application database',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'jax-world-preference-',
      );
      final path = '${dir.path}/jax.db';
      final first = await AppDatabase.open(path);
      final store = SqliteWorldCategoryCollapseStore(first);
      final before = await SqliteSyncSnapshotAdapter(first.database).read();
      await store.setCollapsed('world-category:research', true);
      await store.setCollapsed(
        WorldCategoryCollapseStore.branchKey('node'),
        true,
      );
      final after = await SqliteSyncSnapshotAdapter(first.database).read();
      expect(after.businessFingerprint, before.businessFingerprint);
      await first.close();

      final reopened = await AppDatabase.open(path);
      expect(
        await SqliteWorldCategoryCollapseStore(reopened)
            .loadCollapsedSectionKeys(),
        {
          'world-category:research',
          WorldCategoryCollapseStore.branchKey('node'),
        },
      );
      await reopened.close();
      await dir.delete(recursive: true);
    },
  );

  test(
    'v8 migration creates empty UI preferences without changing Event facts',
    () async {
      sqfliteFfiInit();
      final dir = await Directory.systemTemp.createTemp(
        'jax-world-preference-',
      );
      final path = '${dir.path}/jax.db';
      final old = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 8,
          onCreate: (db, _) async {
            await db.execute(
              'CREATE TABLE events (id TEXT PRIMARY KEY,name TEXT NOT NULL,status TEXT NOT NULL,parent_event_id TEXT,sort_order INTEGER,category_id TEXT,first_started_at_utc INTEGER,completed_at_utc INTEGER,created_at_utc INTEGER NOT NULL,updated_at_utc INTEGER NOT NULL)',
            );
            await db.insert('events', {
              'id': 'old',
              'name': '旧事件',
              'status': 'paused',
              'sort_order': 0,
              'created_at_utc': 1,
              'updated_at_utc': 1,
            });
          },
        ),
      );
      await old.close();

      final database = await AppDatabase.open(path);
      final store = SqliteWorldCategoryCollapseStore(database);
      expect((await database.database.query('events')).single['name'], '旧事件');
      expect(await store.loadCollapsedSectionKeys(), isEmpty);
      expect(
        (await database.database.rawQuery('PRAGMA user_version'))
            .single['user_version'],
        AppDatabase.schemaVersion,
      );
      await database.close();
      await dir.delete(recursive: true);
    },
  );
}
