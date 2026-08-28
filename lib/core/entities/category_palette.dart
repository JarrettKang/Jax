class CategoryPalette {
  const CategoryPalette._();

  static const length = 8;
  static const keys = <int>[0, 1, 2, 3, 4, 5, 6, 7];

  static bool isValid(int key) => key >= 0 && key < length;

  static int leastUsed(Iterable<int> usedKeys) {
    final counts = List<int>.filled(length, 0);
    for (final key in usedKeys) {
      if (isValid(key)) counts[key]++;
    }
    var selected = 0;
    for (var key = 1; key < length; key++) {
      if (counts[key] < counts[selected]) selected = key;
    }
    return selected;
  }
}
