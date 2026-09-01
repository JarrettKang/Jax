enum WorldNodeStatus { inProgress, completed }

const _unchangedWorldNodeParent = Object();
const _unchangedWorldNodeCategory = Object();

class WorldNode {
  const WorldNode({
    required this.id,
    required this.name,
    required this.status,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
    this.parentWorldNodeId,
    this.categoryId,
  });

  final String id;
  final String name;
  final WorldNodeStatus status;
  final String? parentWorldNodeId;
  final String? categoryId;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  WorldNode copyWith({
    String? name,
    WorldNodeStatus? status,
    int? sortOrder,
    DateTime? updatedAt,
    Object? parentWorldNodeId = _unchangedWorldNodeParent,
    Object? categoryId = _unchangedWorldNodeCategory,
  }) => WorldNode(
    id: id,
    name: name ?? this.name,
    status: status ?? this.status,
    parentWorldNodeId: identical(parentWorldNodeId, _unchangedWorldNodeParent)
        ? this.parentWorldNodeId
        : parentWorldNodeId as String?,
    categoryId: identical(categoryId, _unchangedWorldNodeCategory)
        ? this.categoryId
        : categoryId as String?,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
