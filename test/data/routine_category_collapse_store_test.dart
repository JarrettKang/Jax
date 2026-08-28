import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/preferences/routine_category_collapse_store.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/preferences/sqlite_routine_category_collapse_store.dart';

void main() {
  test(
    'Routine Category collapse preferences survive database reopen',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'jax-routine-collapse-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/jax.db';
      var db = await AppDatabase.open(path);
      await SqliteRoutineCategoryCollapseStore(db).setCollapsed(
        RoutineCategoryCollapseStore.sectionKey('stable-id'),
        true,
      );
      await SqliteRoutineCategoryCollapseStore(db)
          .setCollapsed(RoutineCategoryCollapseStore.unclassifiedKey, true);
      await db.close();
      db = await AppDatabase.open(path);
      final keys = await SqliteRoutineCategoryCollapseStore(db)
          .loadCollapsedSectionKeys();
      expect(keys, {
        RoutineCategoryCollapseStore.sectionKey('stable-id'),
        RoutineCategoryCollapseStore.unclassifiedKey,
      });
      await db.close();
    },
  );
}
