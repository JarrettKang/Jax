abstract interface class RoutineCategoryCollapseStore {
  static const unclassifiedKey = 'routine-category:unclassified';
  static String sectionKey(String? id) =>
      id == null ? unclassifiedKey : 'routine-category:$id';
  Future<Set<String>> loadCollapsedSectionKeys();
  Future<void> setCollapsed(String sectionKey, bool collapsed);
}

class InMemoryRoutineCategoryCollapseStore
    implements RoutineCategoryCollapseStore {
  final Set<String> _collapsed = {};
  @override
  Future<Set<String>> loadCollapsedSectionKeys() async => Set.of(_collapsed);
  @override
  Future<void> setCollapsed(String key, bool collapsed) async {
    collapsed ? _collapsed.add(key) : _collapsed.remove(key);
  }
}
