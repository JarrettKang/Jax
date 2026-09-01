import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../entities/world_node_ids.dart';

const syncProtocolVersion = 4;

enum SyncEntityKind {
  eventCategory,
  event,
  eventDayPlan,
  eventRunSegment,
  routineCategory,
  routine,
  routineExecution,
  routineRunSegment,
  worldNode,
  legacyEventWorldNodeLink,
  plan,
  planItem,
}

enum SyncListKind {
  eventCategories,
  eventSiblings,
  routineCategories,
  routines,
  eventDayPlans,
  worldNodeSiblings,
  planItems,
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
    this.datasetGeneration = 'legacy',
    this.protocolVersion = syncProtocolVersion,
    this.warnings = const [],
  }) : records = [...records]..sort((a, b) => a.key.compareTo(b.key)),
       lists = [...lists]..sort((a, b) => a.key.compareTo(b.key));
  final int protocolVersion;
  final int schemaVersion;
  final String datasetGeneration;
  final DateTime exportedAtUtc;
  final List<SyncRecord> records;
  final List<SyncList> lists;
  final List<String> warnings;
  Map<String, Object?> toJson() => {
    'syncProtocolVersion': protocolVersion,
    'schemaVersion': schemaVersion,
    'datasetGeneration': datasetGeneration,
    'exportedAtUtc': exportedAtUtc.millisecondsSinceEpoch,
    'records': records.map((record) => record.toJson()).toList(),
    'lists': lists.map((list) => list.toJson()).toList(),
    'warnings': warnings,
  };
  String toJsonString({bool pretty = false}) =>
      (pretty ? const JsonEncoder.withIndent('  ') : const JsonEncoder())
          .convert(toJson());
  factory SyncSnapshot.fromJson(Map<String, Object?> json) {
    final snapshot = SyncSnapshot(
      protocolVersion: json['syncProtocolVersion']! as int,
      schemaVersion: json['schemaVersion']! as int,
      datasetGeneration: json['datasetGeneration'] as String? ?? 'legacy',
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
    final withWorldNodes = snapshot.protocolVersion == 1
        ? _upgradeProtocol1Baseline(snapshot)
        : snapshot;
    final withPlanning = withWorldNodes.protocolVersion == 2
        ? _upgradeProtocol2Baseline(withWorldNodes)
        : withWorldNodes;
    return withPlanning.protocolVersion == 3
        ? _upgradeProtocol3Baseline(withPlanning)
        : withPlanning;
  }
  factory SyncSnapshot.fromJsonString(String source) => SyncSnapshot.fromJson(
    (jsonDecode(source) as Map).cast<String, Object?>(),
  );
  String get businessFingerprint => jsonEncode({
    'syncProtocolVersion': protocolVersion,
    'datasetGeneration': datasetGeneration,
    // Raw integer order is storage, while [lists] is the canonical business
    // order. Created/updated metadata is comparison evidence, not user state.
    'records': records.map((record) => record.entityFingerprint).toList(),
    'lists': lists.map((list) => list.toJson()).toList(),
  });
  String get businessFingerprintSha256 =>
      sha256.convert(utf8.encode(businessFingerprint)).toString();
}

SyncSnapshot _upgradeProtocol1Baseline(SyncSnapshot source) {
  final events = source.records
      .where(
        (record) => record.kind == SyncEntityKind.event && !record.isDeleted,
      )
      .toList();
  final additions = <SyncRecord>[];
  for (final event in events) {
    final nodeId = WorldNodeIds.fromLegacyEvent(event.metadata.id);
    final parent = event.payload['parentSyncId'] as String?;
    additions.addAll([
      SyncRecord(
        kind: SyncEntityKind.worldNode,
        metadata: SyncMetadata(
          id: nodeId,
          createdAtUtc: event.metadata.createdAtUtc,
          updatedAtUtc: event.metadata.updatedAtUtc,
        ),
        payload: {
          'name': event.payload['name'],
          'status': event.payload['status'] == 'completed'
              ? 'completed'
              : 'inProgress',
          'parentWorldNodeSyncId': parent == null
              ? null
              : WorldNodeIds.fromLegacyEvent(parent),
          'categorySyncId': parent == null
              ? event.payload['categorySyncId']
              : null,
          'order': event.payload['order'],
        },
      ),
      SyncRecord(
        kind: SyncEntityKind.legacyEventWorldNodeLink,
        metadata: SyncMetadata(
          id: event.metadata.id,
          createdAtUtc: event.metadata.createdAtUtc,
          updatedAtUtc: event.metadata.updatedAtUtc,
        ),
        payload: {
          'legacyEventSyncId': event.metadata.id,
          'worldNodeSyncId': nodeId,
        },
      ),
    ]);
  }
  final eventById = {for (final event in events) event.metadata.id: event};
  final rootOrder = source.lists
      .where(
        (list) =>
            list.kind == SyncListKind.eventSiblings && list.scopeId == 'root',
      )
      .firstOrNull
      ?.itemIds;
  final groups = <String, List<String>>{};
  Iterable<SyncRecord> orderedEvents(String? parent) {
    final matching = events.where(
      (event) => event.payload['parentSyncId'] == parent,
    );
    final ids = parent == null
        ? rootOrder
        : source.lists
              .where(
                (list) =>
                    list.kind == SyncListKind.eventSiblings &&
                    list.scopeId == parent,
              )
              .firstOrNull
              ?.itemIds;
    if (ids == null) {
      return matching.toList()..sort((a, b) {
        final order = ((a.payload['order'] as int?) ?? 0).compareTo(
          (b.payload['order'] as int?) ?? 0,
        );
        return order != 0 ? order : a.metadata.id.compareTo(b.metadata.id);
      });
    }
    return ids.map((id) => eventById[id]).nonNulls.where(matching.contains);
  }

  for (final event in events) {
    final parent = event.payload['parentSyncId'] as String?;
    final scope = parent == null
        ? 'category:${event.payload['categorySyncId'] ?? 'uncategorized'}'
        : 'parent:${WorldNodeIds.fromLegacyEvent(parent)}';
    groups.putIfAbsent(scope, () => []);
  }
  for (final parent in <String?>{
    null,
    ...events.map((event) => event.payload['parentSyncId'] as String?),
  }) {
    for (final event in orderedEvents(parent)) {
      final scope = parent == null
          ? 'category:${event.payload['categorySyncId'] ?? 'uncategorized'}'
          : 'parent:${WorldNodeIds.fromLegacyEvent(parent)}';
      groups[scope]!.add(WorldNodeIds.fromLegacyEvent(event.metadata.id));
    }
  }
  return SyncSnapshot(
    protocolVersion: 2,
    schemaVersion: source.schemaVersion,
    exportedAtUtc: source.exportedAtUtc,
    records: [...source.records, ...additions],
    lists: [
      ...source.lists,
      for (final entry in groups.entries)
        if (entry.value.isNotEmpty)
          SyncList(
            kind: SyncListKind.worldNodeSiblings,
            scopeId: entry.key,
            itemIds: entry.value,
          ),
    ],
    warnings: [
      ...source.warnings,
      'baseline-upgraded: sync protocol 1 normalized to protocol 2 WorldNodes',
    ],
  );
}

SyncSnapshot _upgradeProtocol2Baseline(SyncSnapshot source) => SyncSnapshot(
  protocolVersion: 3,
  schemaVersion: source.schemaVersion,
  datasetGeneration: source.datasetGeneration,
  exportedAtUtc: source.exportedAtUtc,
  records: source.records,
  lists: source.lists,
  warnings: [
    ...source.warnings,
    'baseline-upgraded: sync protocol 2 normalized to protocol 3 Planning',
  ],
);

SyncSnapshot _upgradeProtocol3Baseline(SyncSnapshot source) {
  final events = {
    for (final record in source.records.where(
      (record) => record.kind == SyncEntityKind.event && !record.isDeleted,
    ))
      record.metadata.id: record,
  };
  String? effectiveCategory(SyncRecord event) {
    var current = event;
    final seen = <String>{};
    while (seen.add(current.metadata.id)) {
      final parentId = current.payload['parentSyncId'] as String?;
      if (parentId == null) return current.payload['categorySyncId'] as String?;
      final parent = events[parentId];
      if (parent == null) return event.payload['categorySyncId'] as String?;
      current = parent;
    }
    return event.payload['categorySyncId'] as String?;
  }

  final records = <SyncRecord>[];
  for (final record in source.records) {
    if (record.kind == SyncEntityKind.legacyEventWorldNodeLink) continue;
    if (record.kind != SyncEntityKind.event || record.isDeleted) {
      records.add(record);
      continue;
    }
    final payload = Map<String, Object?>.from(record.payload)
      ..remove('parentSyncId')
      ..remove('order')
      ..['sourcePlanItemSyncId'] = null
      ..['categorySyncId'] = effectiveCategory(record);
    records.add(
      SyncRecord(kind: record.kind, metadata: record.metadata, payload: payload),
    );
  }
  return SyncSnapshot(
    protocolVersion: syncProtocolVersion,
    schemaVersion: source.schemaVersion,
    datasetGeneration: 'legacy',
    exportedAtUtc: source.exportedAtUtc,
    records: records,
    lists: source.lists
        .where((list) => list.kind != SyncListKind.eventSiblings)
        .toList(growable: false),
    warnings: [
      ...source.warnings,
      'baseline-upgraded: sync protocol 3 normalized to protocol 4 flat Events',
    ],
  );
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
