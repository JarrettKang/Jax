class PlanReviewNote {
  const PlanReviewNote({
    required this.id,
    required this.planId,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String planId;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;
}
