enum ExecutionSource { event, routine }

class DailyExecutionSegment {
  const DailyExecutionSegment({
    required this.id,
    required this.source,
    required this.ownerId,
    required this.name,
    required this.startedAt,
    required this.createdAt,
    this.endedAt,
    this.detail,
    this.categoryBucketKey = 'unclassified',
    this.categoryName = '未分类',
  });
  final String id, ownerId, name;
  final ExecutionSource source;
  final DateTime startedAt, createdAt;
  final DateTime? endedAt;
  final String? detail;
  final String categoryBucketKey;
  final String categoryName;
  bool get isOpen => endedAt == null;
}
