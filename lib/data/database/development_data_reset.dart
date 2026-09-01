import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app_database.dart';

/// Explicit, local development-data epoch reset.
///
/// Device settings and external sync-storage configuration are outside these
/// tables and remain untouched. Both devices must receive the same generation.
class DevelopmentDataReset {
  const DevelopmentDataReset(this.app);

  final AppDatabase app;

  Future<void> run({required String generation}) async {
    final clean = generation.trim();
    if (clean.isEmpty) throw ArgumentError.value(generation, 'generation');
    await app.database.transaction((tx) async {
      await tx.execute('PRAGMA defer_foreign_keys = ON');
      if (await _tableExists(tx, 'legacy_event_world_node_links')) {
        await tx.delete('legacy_event_world_node_links');
      }
      for (final table in const [
        'event_day_plans',
        'run_segments',
        'events',
        'plan_items',
        'plans',
        'world_nodes',
        'routine_run_segments',
        'routine_executions',
        'routines',
        'routine_categories',
        'categories',
        'world_category_collapse_preferences',
        'routine_category_collapse_preferences',
        'sync_tombstones',
      ]) {
        if (await _tableExists(tx, table)) await tx.delete(table);
      }
      await tx.insert(
        'dataset_metadata',
        {
          'singleton': 1,
          'generation': clean,
          'created_at_utc': DateTime.now().toUtc().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      final foreignKeys = await tx.rawQuery('PRAGMA foreign_key_check');
      if (foreignKeys.isNotEmpty) {
        throw StateError('Reset foreign-key failure: $foreignKeys');
      }
    });
  }

  Future<Map<String, int>> businessCounts() async {
    final result = <String, int>{};
    for (final table in const [
      'categories',
      'world_nodes',
      'plans',
      'plan_items',
      'events',
      'event_day_plans',
      'run_segments',
      'routine_categories',
      'routines',
      'routine_executions',
      'routine_run_segments',
      'sync_tombstones',
    ]) {
      final rows = await app.database.rawQuery(
        'SELECT count(*) count FROM $table',
      );
      result[table] = (rows.single['count'] as num).toInt();
    }
    return result;
  }

  static Future<bool> _tableExists(DatabaseExecutor db, String table) async =>
      (await db.rawQuery(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
        [table],
      )).isNotEmpty;
}
