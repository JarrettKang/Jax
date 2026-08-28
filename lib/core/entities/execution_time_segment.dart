enum ExecutionOwnerType { event, routine }

class ExecutionTimeOwner {
  const ExecutionTimeOwner({
    required this.type,
    required this.id,
    required this.name,
    required this.status,
    this.detail,
  });
  final ExecutionOwnerType type;
  final String id, name, status;
  final String? detail;
}

class ExecutionTimeSegment {
  const ExecutionTimeSegment({
    required this.id,
    required this.ownerType,
    required this.ownerId,
    required this.ownerName,
    required this.startedAt,
    required this.createdAt,
    this.endedAt,
  });
  final String id;
  final ExecutionOwnerType ownerType;
  final String ownerId;
  final String ownerName;
  final DateTime startedAt;
  final DateTime? endedAt;
  final DateTime createdAt;
}
