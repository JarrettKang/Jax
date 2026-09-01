import 'event_status.dart';

const _unchangedCompletedAt = Object();
const _unchangedCategory = Object();

/// A finite, flat execution object.
///
/// Planned Events are identified by [sourcePlanItemId]. Standalone Events
/// leave it null and may own a direct [categoryId].
class JaxEvent {
  const JaxEvent({
    required this.id,
    required this.name,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.sourcePlanItemId,
    this.firstStartedAt,
    this.completedAt,
    this.categoryId,
  });

  final String id;
  final String name;
  final EventStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? sourcePlanItemId;
  final DateTime? firstStartedAt;
  final DateTime? completedAt;
  final String? categoryId;

  bool get isPlanned => sourcePlanItemId != null;
  bool get isStandalone => sourcePlanItemId == null;

  JaxEvent copyWith({
    String? name,
    EventStatus? status,
    DateTime? updatedAt,
    DateTime? firstStartedAt,
    Object? completedAt = _unchangedCompletedAt,
    Object? categoryId = _unchangedCategory,
  }) => JaxEvent(
    id: id,
    name: name ?? this.name,
    status: status ?? this.status,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    sourcePlanItemId: sourcePlanItemId,
    firstStartedAt: firstStartedAt ?? this.firstStartedAt,
    completedAt: identical(completedAt, _unchangedCompletedAt)
        ? this.completedAt
        : completedAt as DateTime?,
    categoryId: identical(categoryId, _unchangedCategory)
        ? this.categoryId
        : categoryId as String?,
  );

  @override
  bool operator ==(Object other) =>
      other is JaxEvent &&
      other.id == id &&
      other.name == name &&
      other.status == status &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      other.sourcePlanItemId == sourcePlanItemId &&
      other.firstStartedAt == firstStartedAt &&
      other.completedAt == completedAt &&
      other.categoryId == categoryId;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    status,
    createdAt,
    updatedAt,
    sourcePlanItemId,
    firstStartedAt,
    completedAt,
    categoryId,
  );
}
