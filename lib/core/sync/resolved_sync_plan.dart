import 'sync_compare_engine.dart';
import 'sync_contract.dart';

class ResolvedSyncPlan {
  const ResolvedSyncPlan({
    required this.preview,
    this.recordChoices = const {},
    this.listChoices = const {},
    this.invariantResolutions = const {},
  });

  final SyncPlan preview;
  final Map<String, SyncSide> recordChoices;
  final Map<String, SyncSide> listChoices;
  final Map<String, SyncInvariantResolution> invariantResolutions;

  List<String> get unresolvedKeys => [
    for (final item in preview.manualConflicts)
      if (!_isSide(recordChoices[item.key])) item.key,
    for (final item in preview.listConflicts)
      if (!_isSide(listChoices[item.key])) item.key,
    for (final item in preview.invariantConflicts)
      if (!invariantResolutions.containsKey(item.key)) item.key,
  ];

  bool _isSide(SyncSide? side) =>
      side == SyncSide.windows || side == SyncSide.android;

  Map<String, Object?> toResolutionJson() => {
    'syncProtocolVersion': preview.protocolVersion,
    'windowsSourceFingerprint': preview.windowsSourceFingerprint,
    'androidSourceFingerprint': preview.androidSourceFingerprint,
    if (preview.baselineFingerprint != null)
      'baselineFingerprint': preview.baselineFingerprint,
    'recordChoices': {
      for (final entry in recordChoices.entries) entry.key: entry.value.name,
    },
    'listChoices': {
      for (final entry in listChoices.entries) entry.key: entry.value.name,
    },
    'invariantResolutions': {
      for (final entry in invariantResolutions.entries)
        entry.key: entry.value.toJson(),
    },
  };

  factory ResolvedSyncPlan.fromResolutionJson(
    SyncPlan preview,
    Map<String, Object?> json,
  ) {
    if (json['syncProtocolVersion'] != preview.protocolVersion ||
        json['windowsSourceFingerprint'] != preview.windowsSourceFingerprint ||
        json['androidSourceFingerprint'] != preview.androidSourceFingerprint ||
        json['baselineFingerprint'] != preview.baselineFingerprint) {
      throw const SyncPlanException(
        'STALE_SYNC_PLAN',
        'Resolution belongs to a different analysis plan.',
      );
    }
    SyncSide side(Object? value) => SyncSide.values.byName(value! as String);
    Map<String, SyncSide> choices(String key) => {
      for (final entry in ((json[key] as Map?) ?? const {}).entries)
        entry.key as String: side(entry.value),
    };
    return ResolvedSyncPlan(
      preview: preview,
      recordChoices: choices('recordChoices'),
      listChoices: choices('listChoices'),
      invariantResolutions: {
        for (final entry
            in ((json['invariantResolutions'] as Map?) ?? const {}).entries)
          entry.key as String: SyncInvariantResolution.fromJson(
            (entry.value as Map).cast<String, Object?>(),
          ),
      },
    );
  }
}

extension SyncInvariantConflictIdentity on SyncInvariantConflict {
  String get key {
    final windows = [...windowsIds]..sort();
    final android = [...androidIds]..sort();
    return '${type.name}:${windows.join(',')}:${android.join(',')}';
  }
}

/// Explicit record overrides required to make a cross-record invariant legal.
/// This avoids inventing a hidden "losing running becomes paused" policy.
class SyncInvariantResolution {
  const SyncInvariantResolution({required this.recordOverrides});
  final Map<String, SyncRecord> recordOverrides;
  Map<String, Object?> toJson() => {
    'recordOverrides': {
      for (final entry in recordOverrides.entries)
        entry.key: entry.value.toJson(),
    },
  };
  factory SyncInvariantResolution.fromJson(Map<String, Object?> json) =>
      SyncInvariantResolution(
        recordOverrides: {
          for (final entry
              in ((json['recordOverrides'] as Map?) ?? const {}).entries)
            entry.key as String: SyncRecord.fromJson(
              (entry.value as Map).cast<String, Object?>(),
            ),
        },
      );
}

class SyncPlanException implements Exception {
  const SyncPlanException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => '$code: $message';
}
