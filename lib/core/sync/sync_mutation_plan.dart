import 'sync_contract.dart';

enum SyncMutationType { deleteRecord, upsertRecord, applyList }

class SyncMutation {
  SyncMutation._({required this.type, this.record, this.list, this.key});
  SyncMutation.deleteRecord(SyncRecord record)
    : this._(
        type: SyncMutationType.deleteRecord,
        record: record,
        key: record.key,
      );
  SyncMutation.upsertRecord(SyncRecord record)
    : this._(
        type: SyncMutationType.upsertRecord,
        record: record,
        key: record.key,
      );
  SyncMutation.applyList(SyncList list)
    : this._(type: SyncMutationType.applyList, list: list, key: list.key);

  final SyncMutationType type;
  final String? key;
  final SyncRecord? record;
  final SyncList? list;

  Map<String, Object?> toJson() => {
    'type': type.name,
    if (key != null) 'key': key,
    if (record != null) 'record': record!.toJson(),
    if (list != null) 'list': list!.toJson(),
  };
}

class SyncMutationPlan {
  SyncMutationPlan({
    required Iterable<SyncMutation> windowsOperations,
    required Iterable<SyncMutation> androidOperations,
    required this.expectedFinalSnapshot,
    required this.windowsSourceFingerprint,
    required this.androidSourceFingerprint,
    required this.baselineFingerprint,
  }) : windowsOperations = List.unmodifiable(windowsOperations),
       androidOperations = List.unmodifiable(androidOperations);

  final List<SyncMutation> windowsOperations;
  final List<SyncMutation> androidOperations;
  final SyncSnapshot expectedFinalSnapshot;
  final String windowsSourceFingerprint;
  final String androidSourceFingerprint;
  final String? baselineFingerprint;

  Map<String, Object?> toJson() => {
    'windowsSourceFingerprint': windowsSourceFingerprint,
    'androidSourceFingerprint': androidSourceFingerprint,
    if (baselineFingerprint != null) 'baselineFingerprint': baselineFingerprint,
    'windowsOperations': windowsOperations
        .map((value) => value.toJson())
        .toList(),
    'androidOperations': androidOperations
        .map((value) => value.toJson())
        .toList(),
    'expectedFinalFingerprint': expectedFinalSnapshot.businessFingerprintSha256,
  };
}
