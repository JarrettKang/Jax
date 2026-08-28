import '../../core/preferences/routine_category_collapse_store.dart';
import '../database/app_database.dart';

class SqliteRoutineCategoryCollapseStore
    implements RoutineCategoryCollapseStore {
  const SqliteRoutineCategoryCollapseStore(this._database);
  final AppDatabase _database;
  @override
  Future<Set<String>> loadCollapsedSectionKeys() async =>
      (await _database.database.query('routine_category_collapse_preferences'))
          .map((row) => row['section_key'] as String)
          .toSet();
  @override
  Future<void> setCollapsed(String key, bool collapsed) async {
    if (collapsed) {
      await _database.database.insert('routine_category_collapse_preferences', {
        'section_key': key,
      });
    } else {
      await _database.database.delete(
        'routine_category_collapse_preferences',
        where: 'section_key = ?',
        whereArgs: [key],
      );
    }
  }
}
