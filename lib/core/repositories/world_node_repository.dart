import '../entities/world_node.dart';

abstract interface class WorldNodeRepository {
  Future<List<WorldNode>> getWorldNodes();
  Future<WorldNode?> getWorldNode(String id);
  Future<void> insertWorldNode(WorldNode node);
  Future<void> updateWorldNode(WorldNode node);
  Future<void> reparentWorldNode(
    String id,
    String? parentWorldNodeId,
    String? categoryId,
    int sortOrder,
    DateTime updatedAt,
  );
  Future<void> reorderWorldNode(String id, int targetIndex);
}
