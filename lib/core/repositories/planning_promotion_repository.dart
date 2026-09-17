import '../entities/world_node.dart';

abstract interface class PlanningPromotionRepository {
  /// Creates a child and converts the original step into a terminal reference.
  Future<WorldNode> promotePlanItem({
    required String planItemId,
    required String worldNodeId,
    required DateTime now,
  });
}
