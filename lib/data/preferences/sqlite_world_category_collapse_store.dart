import '../../core/preferences/world_category_collapse_store.dart';
import '../database/app_database.dart';

/// SQLite-backed storage for World presentation preferences.
///
/// It deliberately owns a UI-only table and has no dependency on Event or
/// Category business data.
class SqliteWorldCategoryCollapseStore implements WorldCategoryCollapseStore {
  SqliteWorldCategoryCollapseStore(this._appDatabase);

  final AppDatabase _appDatabase;

  @override
  Future<Set<String>> loadCollapsedSectionKeys() async =>
      (await _appDatabase.database.query('world_category_collapse_preferences'))
          .map((row) => row['section_key'] as String)
          .toSet();

  @override
  Future<void> setCollapsed(String sectionKey, bool collapsed) async {
    if (collapsed) {
      await _appDatabase.database.insert(
        'world_category_collapse_preferences',
        {'section_key': sectionKey},
      );
    } else {
      await _appDatabase.database.delete(
        'world_category_collapse_preferences',
        where: 'section_key = ?',
        whereArgs: [sectionKey],
      );
    }
  }
}
