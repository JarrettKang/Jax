// draft is a wire/storage compatibility value only. New product writes use next.
enum PlanItemStatus { draft, next, dispatched, done, dropped }

enum PlanItemType { step, worldNodeReference }

PlanItemStatus readPlanItemStatus(String value) => value == 'draft'
    ? PlanItemStatus.next
    : PlanItemStatus.values.byName(value);

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
    this.promotedWorldNodeId,
  });

  final String id;
  final String planId;
  final String title;
  final String? note;
  final PlanItemStatus status;

  /// A reference is terminal, regardless of its retained historical status.
  final String? promotedWorldNodeId;
  PlanItemType get type => promotedWorldNodeId == null
      ? PlanItemType.step
      : PlanItemType.worldNodeReference;
  bool get isPromoted => type == PlanItemType.worldNodeReference;
  bool get isExecutable =>
      !isPromoted &&
      (status == PlanItemStatus.next || status == PlanItemStatus.draft);
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
}
