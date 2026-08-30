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
}

class SyncPlanException implements Exception {
  const SyncPlanException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => '$code: $message';
}
