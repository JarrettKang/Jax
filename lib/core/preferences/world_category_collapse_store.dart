/// Persistent presentation state for World Category sections.
///
/// Keys intentionally identify sections, rather than Category names: renaming
/// a Category must not change its expanded state. This is UI state only and
/// does not belong to the Event or Category domain models.
abstract interface class WorldCategoryCollapseStore {
  static const unclassifiedKey = 'world-category:unclassified';
  // A separate key namespace in the existing device-local presentation store.
  static String branchKey(String nodeId) => 'world-branch:$nodeId';

  static String sectionKey(String? categoryId) =>
      categoryId == null ? unclassifiedKey : 'world-category:$categoryId';

  Future<Set<String>> loadCollapsedSectionKeys();
  Future<void> setCollapsed(String sectionKey, bool collapsed);
}

/// Lightweight fallback for embedders and widget tests that do not provide
/// platform persistence. The production app injects the SQLite implementation.
class InMemoryWorldCategoryCollapseStore implements WorldCategoryCollapseStore {
  final Set<String> _collapsed = {};

  @override
  Future<Set<String>> loadCollapsedSectionKeys() async => Set.of(_collapsed);

  @override
  Future<void> setCollapsed(String sectionKey, bool collapsed) async {
    if (collapsed) {
      _collapsed.add(sectionKey);
    } else {
      _collapsed.remove(sectionKey);
    }
  }
}
