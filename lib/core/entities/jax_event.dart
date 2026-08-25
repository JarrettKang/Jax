import 'event_status.dart';

const _unchangedParent = Object();

class JaxEvent {
  const JaxEvent({
    required this.id,
    required this.name,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.parentEventId,
    this.firstStartedAt,
    this.completedAt,
  });

  final String id;
  final String name;
  final EventStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? parentEventId;
  final DateTime? firstStartedAt;
  final DateTime? completedAt;

  JaxEvent copyWith({
    String? name,
    EventStatus? status,
    DateTime? updatedAt,
    DateTime? firstStartedAt,
    DateTime? completedAt,
    Object? parentEventId = _unchangedParent,
  }) {
    return JaxEvent(
      id: id,
      name: name ?? this.name,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      parentEventId: identical(parentEventId, _unchangedParent)
          ? this.parentEventId
          : parentEventId as String?,
      firstStartedAt: firstStartedAt ?? this.firstStartedAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is JaxEvent &&
        other.id == id &&
        other.name == name &&
        other.status == status &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        other.parentEventId == parentEventId &&
        other.firstStartedAt == firstStartedAt &&
        other.completedAt == completedAt;
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    status,
    createdAt,
    updatedAt,
    parentEventId,
    firstStartedAt,
    completedAt,
  );
}
