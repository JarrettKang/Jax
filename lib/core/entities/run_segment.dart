class RunSegment {
  const RunSegment({
    required this.id,
    required this.eventId,
    required this.startedAt,
    required this.createdAt,
    this.endedAt,
  });
  final String id;
  final String eventId;
  final DateTime startedAt;
  final DateTime createdAt;
  final DateTime? endedAt;
  Duration durationAt(DateTime now) =>
      (endedAt ?? now.toUtc()).difference(startedAt);
  RunSegment copyWith({DateTime? startedAt, DateTime? endedAt}) => RunSegment(
    id: id,
    eventId: eventId,
    startedAt: startedAt ?? this.startedAt,
    createdAt: createdAt,
    endedAt: endedAt ?? this.endedAt,
  );
  @override
  bool operator ==(Object other) =>
      other is RunSegment &&
      other.id == id &&
      other.eventId == eventId &&
      other.startedAt == startedAt &&
      other.endedAt == endedAt &&
      other.createdAt == createdAt;
  @override
  int get hashCode => Object.hash(id, eventId, startedAt, endedAt, createdAt);
}
