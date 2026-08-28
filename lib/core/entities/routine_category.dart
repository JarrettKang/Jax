class RoutineCategory {
  const RoutineCategory({
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  RoutineCategory copyWith({
    String? name,
    int? sortOrder,
    DateTime? updatedAt,
  }) => RoutineCategory(
    id: id,
    name: name ?? this.name,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
