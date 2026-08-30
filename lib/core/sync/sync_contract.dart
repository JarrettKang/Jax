import 'dart:convert';

import 'package:crypto/crypto.dart';

const syncProtocolVersion = 1;

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

enum SyncListKind {
  eventCategories,
  eventSiblings,
  routineCategories,
  routines,
  eventDayPlans,
}

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
  Map<String, Object?> toJson() => {
    'id': id,
    'createdAtUtc': createdAtUtc.millisecondsSinceEpoch,
    'updatedAtUtc': updatedAtUtc.millisecondsSinceEpoch,
    if (deletedAtUtc != null)
      'deletedAtUtc': deletedAtUtc!.millisecondsSinceEpoch,
  };
  factory SyncMetadata.fromJson(Map<String, Object?> json) => SyncMetadata(
    id: json['id']! as String,
    createdAtUtc: DateTime.fromMillisecondsSinceEpoch(
      json['createdAtUtc']! as int,
      isUtc: true,
    ),
    updatedAtUtc: DateTime.fromMillisecondsSinceEpoch(
      json['updatedAtUtc']! as int,
      isUtc: true,
    ),
    deletedAtUtc: json['deletedAtUtc'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            json['deletedAtUtc']! as int,
            isUtc: true,
          ),
  );
}

class SyncRecord {
  const SyncRecord({
    required this.kind,
    required this.metadata,
    required this.payload,
  });
  final SyncEntityKind kind;
  final SyncMetadata metadata;
  final Map<String, Object?> payload;
  String get key => '${kind.name}:${metadata.id}';
  bool get isDeleted => metadata.deletedAtUtc != null;
  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'metadata': metadata.toJson(),
    'payload': _sortedMap(payload),
  };
  factory SyncRecord.fromJson(Map<String, Object?> json) => SyncRecord(
    kind: SyncEntityKind.values.byName(json['kind']! as String),
    metadata: SyncMetadata.fromJson(
      (json['metadata']! as Map).cast<String, Object?>(),
    ),
    payload: (json['payload']! as Map).cast<String, Object?>(),
  );
  String get businessFingerprint => jsonEncode({
    'kind': kind.name,
    'id': metadata.id,
    'deletedAtUtc': metadata.deletedAtUtc?.millisecondsSinceEpoch,
    'payload': _sortedMap(payload),
  });

  String get entityFingerprint {
    final fields = Map<String, Object?>.from(payload)..remove('order');
    return jsonEncode({
      'kind': kind.name,
      'id': metadata.id,
      'deleted': isDeleted,
      'payload': _sortedMap(fields),
    });
  }
}

class SyncList {
  const SyncList({
    required this.kind,
    required this.scopeId,
    required this.itemIds,
  });
  final SyncListKind kind;
  final String scopeId;
  final List<String> itemIds;
  String get key => '${kind.name}:$scopeId';
  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'scopeId': scopeId,
    'itemIds': itemIds,
  };
  factory SyncList.fromJson(Map<String, Object?> json) => SyncList(
    kind: SyncListKind.values.byName(json['kind']! as String),
    scopeId: json['scopeId']! as String,
    itemIds: (json['itemIds']! as List).cast<String>(),
  );
}

class SyncSnapshot {
  SyncSnapshot({
    required this.schemaVersion,
    required this.exportedAtUtc,
    required Iterable<SyncRecord> records,
    required Iterable<SyncList> lists,
    this.protocolVersion = syncProtocolVersion,
    this.warnings = const [],
  }) : records = [...records]..sort((a, b) => a.key.compareTo(b.key)),
       lists = [...lists]..sort((a, b) => a.key.compareTo(b.key));
  final int protocolVersion;
  final int schemaVersion;
  final DateTime exportedAtUtc;
  final List<SyncRecord> records;
  final List<SyncList> lists;
  final List<String> warnings;
  Map<String, Object?> toJson() => {
    'syncProtocolVersion': protocolVersion,
    'schemaVersion': schemaVersion,
    'exportedAtUtc': exportedAtUtc.millisecondsSinceEpoch,
    'records': records.map((record) => record.toJson()).toList(),
    'lists': lists.map((list) => list.toJson()).toList(),
    'warnings': warnings,
  };
  String toJsonString({bool pretty = false}) =>
      (pretty ? const JsonEncoder.withIndent('  ') : const JsonEncoder())
          .convert(toJson());
  factory SyncSnapshot.fromJson(Map<String, Object?> json) => SyncSnapshot(
    protocolVersion: json['syncProtocolVersion']! as int,
    schemaVersion: json['schemaVersion']! as int,
    exportedAtUtc: DateTime.fromMillisecondsSinceEpoch(
      json['exportedAtUtc']! as int,
      isUtc: true,
    ),
    records: (json['records']! as List).map(
      (value) => SyncRecord.fromJson((value as Map).cast<String, Object?>()),
    ),
    lists: (json['lists']! as List).map(
      (value) => SyncList.fromJson((value as Map).cast<String, Object?>()),
    ),
    warnings: (json['warnings'] as List? ?? const []).cast<String>(),
  );
  factory SyncSnapshot.fromJsonString(String source) => SyncSnapshot.fromJson(
    (jsonDecode(source) as Map).cast<String, Object?>(),
  );
  String get businessFingerprint => jsonEncode({
    'syncProtocolVersion': protocolVersion,
    // Raw integer order is storage, while [lists] is the canonical business
    // order. Created/updated metadata is comparison evidence, not user state.
    'records': records.map((record) => record.entityFingerprint).toList(),
    'lists': lists.map((list) => list.toJson()).toList(),
  });
  String get businessFingerprintSha256 =>
      sha256.convert(utf8.encode(businessFingerprint)).toString();
}

Map<String, Object?> _sortedMap(Map<String, Object?> source) {
  final result = <String, Object?>{};
  for (final key in source.keys.toList()..sort()) {
    final value = source[key];
    result[key] = value is Map
        ? _sortedMap(value.cast<String, Object?>())
        : value;
  }
  return result;
}
