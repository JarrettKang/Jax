enum PlanStatus { focused, waiting, ended }

class Plan {
  const Plan({
    required this.id,
    required this.worldNodeId,
    required this.status,
    required this.roundNumber,
    required this.createdAt,
    required this.updatedAt,
    this.title,
    this.endedAt,
  });

  final String id;
  final String worldNodeId;
  final PlanStatus status;
  final int roundNumber;
  final String? title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? endedAt;

  String get displayTitle =>
      title?.trim().isNotEmpty == true ? title!.trim() : '第 $roundNumber 轮计划';

  bool get isCurrent => status != PlanStatus.ended;
}
