import 'event_status.dart';

const _unchangedParent = Object();
const _unchangedSortOrder = Object();
const _unchangedCompletedAt = Object();

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
    this.sortOrder,
  });

  final String id;
  final String name;
  final EventStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? parentEventId;
  final DateTime? firstStartedAt;
  final DateTime? completedAt;
  final int? sortOrder;

  JaxEvent copyWith({
    String? name,
    EventStatus? status,
    DateTime? updatedAt,
    DateTime? firstStartedAt,
    Object? completedAt = _unchangedCompletedAt,
    Object? parentEventId = _unchangedParent,
    Object? sortOrder = _unchangedSortOrder,
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
      completedAt: identical(completedAt, _unchangedCompletedAt)
          ? this.completedAt
          : completedAt as DateTime?,
      sortOrder: identical(sortOrder, _unchangedSortOrder)
          ? this.sortOrder
          : sortOrder as int?,
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
