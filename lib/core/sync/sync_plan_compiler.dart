import 'dart:collection';

import 'resolved_sync_plan.dart';
import 'sync_compare_engine.dart';
import 'sync_contract.dart';
import 'sync_mutation_plan.dart';
import 'sync_snapshot_validator.dart';

class SyncPlanCompiler {
  const SyncPlanCompiler({this.validator = const SyncSnapshotValidator()});
  final SyncSnapshotValidator validator;

  SyncMutationPlan compile({
    required ResolvedSyncPlan resolved,
    required SyncSnapshot windows,
    required SyncSnapshot android,
    SyncSnapshot? baseline,
  }) {
    final preview = resolved.preview;
    _assertSources(preview, windows, android, baseline);
    if (resolved.unresolvedKeys.isNotEmpty) {
      throw SyncPlanException(
        'PLAN_NOT_RESOLVED',
        'Missing resolutions: ${resolved.unresolvedKeys.join(', ')}',
      );
    }

    final records = <String, SyncRecord>{};
    for (final item in preview.items) {
      final selected =
          item.classification == SyncMergeClassification.manualConflict
          ? _fromSide(item, resolved.recordChoices[item.key]!)
          : _automatic(item);
      if (selected != null) records[item.key] = selected;
    }
    final previewKeys = preview.items.map((item) => item.key).toSet();
    for (final resolution in resolved.invariantResolutions.values) {
      for (final entry in resolution.recordOverrides.entries) {
        if (entry.key != entry.value.key || !previewKeys.contains(entry.key)) {
          throw SyncPlanException(
            'PLAN_INVALID',
            'Invariant override is outside the analyzed plan: ${entry.key}.',
          );
        }
        records[entry.key] = entry.value;
      }
    }

    final lists = _mergeLists(resolved, windows, android, records);
    final expected = SyncSnapshot(
      protocolVersion: windows.protocolVersion,
      schemaVersion: windows.schemaVersion,
      exportedAtUtc: windows.exportedAtUtc.isAfter(android.exportedAtUtc)
          ? windows.exportedAtUtc
          : android.exportedAtUtc,
      records: records.values,
      lists: lists,
      warnings: const [],
    );
    final issues = validator.validate(expected);
    if (issues.isNotEmpty) {
      throw SyncPlanException('PLAN_INVALID', issues.join('; '));
    }

    return SyncMutationPlan(
      windowsOperations: _operations(windows, expected),
      androidOperations: _operations(android, expected),
      expectedFinalSnapshot: expected,
      windowsSourceFingerprint: preview.windowsSourceFingerprint,
      androidSourceFingerprint: preview.androidSourceFingerprint,
      baselineFingerprint: preview.baselineFingerprint,
    );
  }

  void _assertSources(
    SyncPlan preview,
    SyncSnapshot windows,
    SyncSnapshot android,
    SyncSnapshot? baseline,
  ) {
    if (preview.protocolVersion != syncProtocolVersion ||
        windows.protocolVersion != preview.protocolVersion ||
        android.protocolVersion != preview.protocolVersion) {
      throw const SyncPlanException(
        'STALE_SYNC_PLAN',
        'Sync protocol changed after analysis; run analysis again.',
      );
    }
    if (windows.businessFingerprintSha256 != preview.windowsSourceFingerprint ||
        android.businessFingerprintSha256 != preview.androidSourceFingerprint) {
      throw const SyncPlanException(
        'STALE_SYNC_PLAN',
        'Source data changed after analysis; run analysis again.',
      );
    }
    if (preview.hasBaseline != (baseline != null) ||
        baseline?.businessFingerprintSha256 != preview.baselineFingerprint) {
      throw const SyncPlanException(
        'STALE_SYNC_PLAN',
        'The successful-sync baseline changed after analysis.',
      );
    }
  }

  SyncRecord? _fromSide(SyncPlanItem item, SyncSide side) => switch (side) {
    SyncSide.windows => item.windows,
    SyncSide.android => item.android,
    SyncSide.unresolved => throw const SyncPlanException(
      'PLAN_NOT_RESOLVED',
      'A manual conflict is unresolved.',
    ),
  };

  SyncRecord? _automatic(SyncPlanItem item) {
    if (item.windows == null) return item.android;
    if (item.android == null) return item.windows;
    if (item.windows!.entityFingerprint == item.android!.entityFingerprint) {
      return item.windows;
    }
    final base = item.baseline;
    if (base != null) {
      if (item.windows!.entityFingerprint == base.entityFingerprint) {
        return item.android;
      }
      if (item.android!.entityFingerprint == base.entityFingerprint) {
        return item.windows;
      }
    }
    // This branch is reachable for same deletion facts with different metadata.
    if (item.windows!.isDeleted && item.android!.isDeleted) return item.windows;
    throw SyncPlanException(
      'PLAN_NOT_RESOLVED',
      'No deterministic automatic result for ${item.key}.',
    );
  }

  List<SyncList> _mergeLists(
    ResolvedSyncPlan resolved,
    SyncSnapshot windows,
    SyncSnapshot android,
    Map<String, SyncRecord> records,
  ) {
    final wm = {for (final list in windows.lists) list.key: list};
    final am = {for (final list in android.lists) list.key: list};
    final conflicts = {
      for (final item in resolved.preview.listConflicts) item.key: item,
    };
    final result = <SyncList>[];
    for (final key in {...wm.keys, ...am.keys}.toList()..sort()) {
      final w = wm[key], a = am[key];
      final template = w ?? a!;
      List<String> ids;
      if (conflicts.containsKey(key)) {
        final side = resolved.listChoices[key]!;
        final primary = side == SyncSide.windows
            ? w?.itemIds ?? const []
            : a?.itemIds ?? const [];
        final secondary = side == SyncSide.windows
            ? a?.itemIds ?? const []
            : w?.itemIds ?? const [];
        ids = [...primary, ...secondary.where((id) => !primary.contains(id))];
      } else {
        ids = _stableMerge(w?.itemIds ?? const [], a?.itemIds ?? const []);
      }
      ids = ids.where((id) => _belongs(template, id, records)).toList();
      if (ids.isNotEmpty) {
        result.add(
          SyncList(
            kind: template.kind,
            scopeId: template.scopeId,
            itemIds: ids,
          ),
        );
      }
    }
    return result;
  }

  List<String> _stableMerge(List<String> first, List<String> second) {
    final nodes = {...first, ...second};
    final edges = {for (final node in nodes) node: <String>{}};
    final indegree = {for (final node in nodes) node: 0};
    for (final list in [first, second]) {
      for (var i = 0; i + 1 < list.length; i++) {
        if (edges[list[i]]!.add(list[i + 1])) {
          indegree[list[i + 1]] = indegree[list[i + 1]]! + 1;
        }
      }
    }
    final ready = SplayTreeSet<String>()
      ..addAll(nodes.where((node) => indegree[node] == 0));
    final result = <String>[];
    while (ready.isNotEmpty) {
      final node = ready.first;
      ready.remove(node);
      result.add(node);
      for (final next in edges[node]!.toList()..sort()) {
        indegree[next] = indegree[next]! - 1;
        if (indegree[next] == 0) ready.add(next);
      }
    }
    if (result.length != nodes.length) {
      throw const SyncPlanException(
        'PLAN_INVALID',
        'Compatible list merge produced a cycle.',
      );
    }
    return result;
  }

  bool _belongs(SyncList list, String id, Map<String, SyncRecord> records) {
    SyncRecord? find(SyncEntityKind kind) => records['${kind.name}:$id'];
    final record = switch (list.kind) {
      SyncListKind.eventCategories => find(SyncEntityKind.eventCategory),
      SyncListKind.eventSiblings => find(SyncEntityKind.event),
      SyncListKind.routineCategories => find(SyncEntityKind.routineCategory),
      SyncListKind.routines => find(SyncEntityKind.routine),
      SyncListKind.eventDayPlans =>
        records.values
            .where(
              (r) =>
                  r.kind == SyncEntityKind.eventDayPlan &&
                  r.payload['eventSyncId'] == id &&
                  r.payload['jaxDay'] == list.scopeId,
            )
            .firstOrNull,
      SyncListKind.worldNodeSiblings => find(SyncEntityKind.worldNode),
      SyncListKind.planItems => find(SyncEntityKind.planItem),
    };
    if (record == null || record.isDeleted) return false;
    return switch (list.kind) {
      SyncListKind.eventSiblings =>
        (record.payload['parentSyncId'] ?? 'root') == list.scopeId,
      SyncListKind.routines =>
        (record.payload['routineCategorySyncId'] ?? 'uncategorized') ==
            list.scopeId,
      SyncListKind.worldNodeSiblings =>
        (record.payload['parentWorldNodeSyncId'] == null
                ? 'category:${record.payload['categorySyncId'] ?? 'uncategorized'}'
                : 'parent:${record.payload['parentWorldNodeSyncId']}') ==
            list.scopeId,
      SyncListKind.planItems => record.payload['planSyncId'] == list.scopeId,
      _ => true,
    };
  }

  List<SyncMutation> _operations(SyncSnapshot source, SyncSnapshot expected) {
    final current = {for (final record in source.records) record.key: record};
    final finalRecords = {
      for (final record in expected.records) record.key: record,
    };
    final operations = <SyncMutation>[];
    for (final key in {
      ...current.keys,
      ...finalRecords.keys,
    }.toList()..sort()) {
      final before = current[key], after = finalRecords[key];
      if (after == null) continue;
      if (after.isDeleted) {
        if (before == null || !before.isDeleted) {
          operations.add(SyncMutation.deleteRecord(after));
        }
      } else if (before == null ||
          before.isDeleted ||
          before.entityFingerprint != after.entityFingerprint) {
        operations.add(SyncMutation.upsertRecord(after));
      }
    }
    final currentLists = {for (final list in source.lists) list.key: list};
    for (final list in expected.lists) {
      final before = currentLists[list.key]?.itemIds ?? const <String>[];
      if (!_listEqual(before, list.itemIds)) {
        operations.add(SyncMutation.applyList(list));
      }
    }
    operations.sort(
      (a, b) =>
          '${a.type.index}:${a.key}'.compareTo('${b.type.index}:${b.key}'),
    );
    return operations;
  }

  bool _listEqual(List<String> a, List<String> b) =>
      a.length == b.length &&
      List.generate(a.length, (i) => a[i] == b[i]).every((same) => same);
}
