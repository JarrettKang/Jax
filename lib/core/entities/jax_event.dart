import 'event_status.dart';

const _unchangedParent = Object();
const _unchangedSortOrder = Object();

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
    DateTime? completedAt,
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
      completedAt: completedAt ?? this.completedAt,
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
        other.completedAt == completedAt &&
        other.sortOrder == sortOrder;
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
    sortOrder,
  );
}
