enum PlanItemStatus { draft, next, dispatched, done, dropped }

class PlanItem {
  const PlanItem({
    required this.id,
    required this.planId,
    required this.title,
    required this.status,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
    this.note,
  });

  final String id;
  final String planId;
  final String title;
  final String? note;
  final PlanItemStatus status;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
}
