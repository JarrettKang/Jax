class Category {
  const Category({
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
    this.colorKey = 0,
  });
  final String id;
  final String name;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int colorKey;

  Category copyWith({
    String? name,
    int? sortOrder,
    DateTime? updatedAt,
    int? colorKey,
  }) => Category(
    id: id,
    name: name ?? this.name,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    colorKey: colorKey ?? this.colorKey,
  );
}
