/// Device-independent entity kinds used by snapshot sync.
enum SyncEntityKind {
  eventCategory,
  event,
  eventDayPlan,
  eventRunSegment,
  routineCategory,
  routine,
  routineExecution,
  routineRunSegment,
}

/// Metadata shared by every entity in the sync contract.
///
/// [id] is the persisted UUID already used as the local TEXT primary key. For
/// an Event day plan it is the deterministic `<event UUID>@<JaxDay key>`.
class SyncMetadata {
  const SyncMetadata({
    required this.id,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    this.deletedAtUtc,
  });

  final String id;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;
  final DateTime? deletedAtUtc;
}

/// Transport-neutral Phase 1 contract. Payload relations must use global UUIDs
/// (for example `parentSyncId`), never database-local row numbers.
class SyncRecord {
  const SyncRecord({
    required this.kind,
    required this.metadata,
    required this.payload,
  });

  final SyncEntityKind kind;
  final SyncMetadata metadata;
  final Map<String, Object?> payload;
}

class SyncSnapshot {
  const SyncSnapshot({required this.schemaVersion, required this.records});

  final int schemaVersion;
  final List<SyncRecord> records;
}
