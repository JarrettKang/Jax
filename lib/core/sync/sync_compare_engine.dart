import 'dart:convert';

import 'sync_contract.dart';

enum SyncComparisonKind {
  same,
  onlyWindows,
  onlyAndroid,
  different,
  deletedWindows,
  deletedAndroid,
  deletedBoth,
}

enum SyncMergeClassification {
  same,
  autoMergeable,
  manualConflict,
  listConflict,
  invariantConflict,
}

enum SyncConflictType {
  entity,
  field,
  hierarchy,
  deleteModify,
  unknownHistory,
  list,
  globalOneRunning,
  openSegment,
  segmentOverlap,
}

enum SyncSide { windows, android, unresolved }

class SyncFieldDiff {
  const SyncFieldDiff({
    required this.field,
    this.windowsValue,
    this.androidValue,
    this.baselineValue,
    this.windowsDisplay,
    this.androidDisplay,
  });
  final String field;
  final Object? windowsValue;
  final Object? androidValue;
  final Object? baselineValue;
  final String? windowsDisplay;
  final String? androidDisplay;
  Map<String, Object?> toJson() => {
    'field': field,
    'windows': windowsValue,
    'android': androidValue,
    if (baselineValue != null) 'baseline': baselineValue,
    if (windowsDisplay != null) 'windowsDisplay': windowsDisplay,
    if (androidDisplay != null) 'androidDisplay': androidDisplay,
  };
  factory SyncFieldDiff.fromJson(Map<String, Object?> json) => SyncFieldDiff(
    field: json['field']! as String,
    windowsValue: json['windows'],
    androidValue: json['android'],
    baselineValue: json['baseline'],
    windowsDisplay: json['windowsDisplay'] as String?,
    androidDisplay: json['androidDisplay'] as String?,
  );
}

class SyncPlanItem {
  const SyncPlanItem({
    required this.key,
    required this.title,
    required this.comparison,
    required this.classification,
    this.conflictType,
    this.windows,
    this.android,
    this.baseline,
    this.changedFields = const [],
    this.detail,
    this.unknownHistory = false,
    this.proposedSide = SyncSide.unresolved,
  });
  final String key;
  final String title;
  final SyncComparisonKind comparison;
  final SyncMergeClassification classification;
  final SyncConflictType? conflictType;
  final SyncRecord? windows;
  final SyncRecord? android;
  final SyncRecord? baseline;
  final List<SyncFieldDiff> changedFields;
  final String? detail;
  final bool unknownHistory;
  final SyncSide proposedSide;

  SyncPlanItem choose(SyncSide side) => SyncPlanItem(
    key: key,
    title: title,
    comparison: comparison,
    classification: classification,
    conflictType: conflictType,
    windows: windows,
    android: android,
    baseline: baseline,
    changedFields: changedFields,
    detail: detail,
    unknownHistory: unknownHistory,
    proposedSide: side,
  );
  Map<String, Object?> toJson() => {
    'key': key,
    'title': title,
    'comparison': comparison.name,
    'classification': classification.name,
    if (conflictType != null) 'conflictType': conflictType!.name,
    if (windows != null) 'windows': windows!.toJson(),
    if (android != null) 'android': android!.toJson(),
    if (baseline != null) 'baseline': baseline!.toJson(),
    'changedFields': changedFields.map((field) => field.toJson()).toList(),
    if (detail != null) 'detail': detail,
    'unknownHistory': unknownHistory,
    'proposedSide': proposedSide.name,
  };
  factory SyncPlanItem.fromJson(Map<String, Object?> json) => SyncPlanItem(
    key: json['key']! as String,
    title: json['title']! as String,
    comparison: SyncComparisonKind.values.byName(json['comparison']! as String),
    classification: SyncMergeClassification.values.byName(
      json['classification']! as String,
    ),
    conflictType: json['conflictType'] == null
        ? null
        : SyncConflictType.values.byName(json['conflictType']! as String),
    windows: json['windows'] == null
        ? null
        : SyncRecord.fromJson(
            (json['windows']! as Map).cast<String, Object?>(),
          ),
    android: json['android'] == null
        ? null
        : SyncRecord.fromJson(
            (json['android']! as Map).cast<String, Object?>(),
          ),
    baseline: json['baseline'] == null
        ? null
        : SyncRecord.fromJson(
            (json['baseline']! as Map).cast<String, Object?>(),
          ),
    changedFields: (json['changedFields']! as List)
        .map(
          (value) =>
              SyncFieldDiff.fromJson((value as Map).cast<String, Object?>()),
        )
        .toList(),
    detail: json['detail'] as String?,
    unknownHistory: json['unknownHistory'] as bool? ?? false,
    proposedSide: SyncSide.values.byName(json['proposedSide']! as String),
  );
}

class SyncListConflict {
  const SyncListConflict({
    required this.key,
    required this.title,
    required this.windowsIds,
    required this.androidIds,
    this.windowsLabels = const [],
    this.androidLabels = const [],
    this.baselineIds,
    this.proposedSide = SyncSide.unresolved,
  });
  final String key;
  final String title;
  final List<String> windowsIds;
  final List<String> androidIds;
  final List<String> windowsLabels;
  final List<String> androidLabels;
  final List<String>? baselineIds;
  final SyncSide proposedSide;
  SyncListConflict choose(SyncSide side) => SyncListConflict(
    key: key,
    title: title,
    windowsIds: windowsIds,
    androidIds: androidIds,
    windowsLabels: windowsLabels,
    androidLabels: androidLabels,
    baselineIds: baselineIds,
    proposedSide: side,
  );
  Map<String, Object?> toJson() => {
    'key': key,
    'title': title,
    'windowsIds': windowsIds,
    'androidIds': androidIds,
    'windowsLabels': windowsLabels,
    'androidLabels': androidLabels,
    if (baselineIds != null) 'baselineIds': baselineIds,
    'proposedSide': proposedSide.name,
  };
  factory SyncListConflict.fromJson(
    Map<String, Object?> json,
  ) => SyncListConflict(
    key: json['key']! as String,
    title: json['title']! as String,
    windowsIds: (json['windowsIds']! as List).cast<String>(),
    androidIds: (json['androidIds']! as List).cast<String>(),
    windowsLabels: (json['windowsLabels'] as List? ?? const []).cast<String>(),
    androidLabels: (json['androidLabels'] as List? ?? const []).cast<String>(),
    baselineIds: (json['baselineIds'] as List?)?.cast<String>(),
    proposedSide: SyncSide.values.byName(json['proposedSide']! as String),
  );
}

class SyncInvariantConflict {
  const SyncInvariantConflict({
    required this.type,
    required this.title,
    required this.detail,
    this.windowsIds = const [],
    this.androidIds = const [],
    this.proposedSide = SyncSide.unresolved,
  });
  final SyncConflictType type;
  final String title;
  final String detail;
  final List<String> windowsIds;
  final List<String> androidIds;
  final SyncSide proposedSide;
  SyncInvariantConflict choose(SyncSide side) => SyncInvariantConflict(
    type: type,
    title: title,
    detail: detail,
    windowsIds: windowsIds,
    androidIds: androidIds,
    proposedSide: side,
  );
  Map<String, Object?> toJson() => {
    'type': type.name,
    'title': title,
    'detail': detail,
    'windowsIds': windowsIds,
    'androidIds': androidIds,
    'proposedSide': proposedSide.name,
  };
  factory SyncInvariantConflict.fromJson(Map<String, Object?> json) =>
      SyncInvariantConflict(
        type: SyncConflictType.values.byName(json['type']! as String),
        title: json['title']! as String,
        detail: json['detail']! as String,
        windowsIds: (json['windowsIds']! as List).cast<String>(),
        androidIds: (json['androidIds']! as List).cast<String>(),
        proposedSide: SyncSide.values.byName(json['proposedSide']! as String),
      );
}

class SyncPlan {
  const SyncPlan({
    required this.hasBaseline,
    required this.items,
    required this.listConflicts,
    required this.invariantConflicts,
    required this.warnings,
    required this.windowsSourceFingerprint,
    required this.androidSourceFingerprint,
    this.baselineFingerprint,
    this.protocolVersion = syncProtocolVersion,
  });
  final bool hasBaseline;
  final List<SyncPlanItem> items;
  final List<SyncListConflict> listConflicts;
  final List<SyncInvariantConflict> invariantConflicts;
  final List<String> warnings;
  final String windowsSourceFingerprint;
  final String androidSourceFingerprint;
  final String? baselineFingerprint;
  final int protocolVersion;
  Iterable<SyncPlanItem> get same => items.where(
    (item) => item.classification == SyncMergeClassification.same,
  );
  Iterable<SyncPlanItem> get autoMergeable => items.where(
    (item) => item.classification == SyncMergeClassification.autoMergeable,
  );
  Iterable<SyncPlanItem> get manualConflicts => items.where(
    (item) => item.classification == SyncMergeClassification.manualConflict,
  );
  int count(SyncComparisonKind kind) =>
      items.where((item) => item.comparison == kind).length;
  Map<String, Object?> toJson() => {
    'phase': 'preview-only',
    'hasBaseline': hasBaseline,
    'syncProtocolVersion': protocolVersion,
    'windowsSourceFingerprint': windowsSourceFingerprint,
    'androidSourceFingerprint': androidSourceFingerprint,
    if (baselineFingerprint != null) 'baselineFingerprint': baselineFingerprint,
    'summary': {
      'same': same.length,
      'onlyWindows': count(SyncComparisonKind.onlyWindows),
      'onlyAndroid': count(SyncComparisonKind.onlyAndroid),
      'different': count(SyncComparisonKind.different),
      'deletedWindows': count(SyncComparisonKind.deletedWindows),
      'deletedAndroid': count(SyncComparisonKind.deletedAndroid),
      'deletedBoth': count(SyncComparisonKind.deletedBoth),
      'autoMergeable': autoMergeable.length,
      'manualConflicts': manualConflicts.length,
      'listConflicts': listConflicts.length,
      'invariantConflicts': invariantConflicts.length,
      'warnings': warnings.length,
    },
    'items': items.map((item) => item.toJson()).toList(),
    'listConflicts': listConflicts.map((item) => item.toJson()).toList(),
    'invariantConflicts': invariantConflicts
        .map((item) => item.toJson())
        .toList(),
    'warnings': warnings,
  };
  String toJsonString({bool pretty = true}) =>
      (pretty ? const JsonEncoder.withIndent('  ') : const JsonEncoder())
          .convert(toJson());
  factory SyncPlan.fromJson(Map<String, Object?> json) => SyncPlan(
    hasBaseline: json['hasBaseline']! as bool,
    windowsSourceFingerprint: json['windowsSourceFingerprint']! as String,
    androidSourceFingerprint: json['androidSourceFingerprint']! as String,
    baselineFingerprint: json['baselineFingerprint'] as String?,
    protocolVersion: json['syncProtocolVersion'] as int? ?? syncProtocolVersion,
    items: (json['items']! as List)
        .map(
          (value) =>
              SyncPlanItem.fromJson((value as Map).cast<String, Object?>()),
        )
        .toList(),
    listConflicts: (json['listConflicts']! as List)
        .map(
          (value) =>
              SyncListConflict.fromJson((value as Map).cast<String, Object?>()),
        )
        .toList(),
    invariantConflicts: (json['invariantConflicts']! as List)
        .map(
          (value) => SyncInvariantConflict.fromJson(
            (value as Map).cast<String, Object?>(),
          ),
        )
        .toList(),
    warnings: (json['warnings']! as List).cast<String>(),
  );
  factory SyncPlan.fromJsonString(String source) =>
      SyncPlan.fromJson((jsonDecode(source) as Map).cast<String, Object?>());
}

class SyncCompareEngine {
  const SyncCompareEngine();

  SyncPlan compare({
    required SyncSnapshot windows,
    required SyncSnapshot android,
    SyncSnapshot? baseline,
  }) {
    _checkProtocol(windows, android, baseline);
    final win = {for (final record in windows.records) record.key: record};
    final phone = {for (final record in android.records) record.key: record};
    final base = {
      for (final record in baseline?.records ?? const <SyncRecord>[])
        record.key: record,
    };
    final keys = {...win.keys, ...phone.keys, ...base.keys}.toList()..sort();
    final items = [
      for (final key in keys)
        _compareRecord(
          key,
          win[key],
          phone[key],
          base[key],
          baseline != null,
          win,
          phone,
        ),
    ];
    return SyncPlan(
      hasBaseline: baseline != null,
      windowsSourceFingerprint: windows.businessFingerprintSha256,
      androidSourceFingerprint: android.businessFingerprintSha256,
      baselineFingerprint: baseline?.businessFingerprintSha256,
      items: items,
      listConflicts: _compareLists(windows, android, baseline),
      invariantConflicts: _invariants(windows, android),
      warnings: [
        ...windows.warnings.map((warning) => 'Windows: $warning'),
        ...android.warnings.map((warning) => 'Android: $warning'),
        if (baseline == null) 'No Last Successful Sync Baseline: divergent identities use UnknownHistory and are never resolved by updatedAt.',
      ],
    );
  }

  void _checkProtocol(
    SyncSnapshot windows,
    SyncSnapshot android,
    SyncSnapshot? baseline,
  ) {
    final versions = {
      windows.protocolVersion,
      android.protocolVersion,
      if (baseline != null) baseline.protocolVersion,
    };
    if (versions.length != 1 || versions.single != syncProtocolVersion) {
      throw StateError('Incompatible sync protocol versions: $versions');
    }
  }

  SyncPlanItem _compareRecord(
    String key,
    SyncRecord? w,
    SyncRecord? a,
    SyncRecord? b,
    bool hasBaseline,
    Map<String, SyncRecord> win,
    Map<String, SyncRecord> phone,
  ) {
    final comparison = _comparison(w, a);
    final fields = _fieldDiffs(w, a, b, win, phone);
    final title = _title(w ?? a ?? b!, win, phone);
    if (_same(w, a)) {
      return SyncPlanItem(
        key: key,
        title: title,
        comparison: comparison,
        classification: SyncMergeClassification.same,
        windows: w,
        android: a,
        baseline: b,
      );
    }

    final deleteExisting = w != null && a != null && w.isDeleted != a.isDeleted;
    if (!hasBaseline) {
      if (w == null || a == null) {
        return SyncPlanItem(
          key: key,
          title: title,
          comparison: comparison,
          classification: SyncMergeClassification.autoMergeable,
          windows: w,
          android: a,
          changedFields: fields,
          detail: 'Identity exists on one side only.',
        );
      }
      return SyncPlanItem(
        key: key,
        title: title,
        comparison: comparison,
        classification: SyncMergeClassification.manualConflict,
        conflictType: deleteExisting
            ? SyncConflictType.deleteModify
            : _fieldType(fields),
        windows: w,
        android: a,
        changedFields: fields,
        detail: deleteExisting ? _deleteDetail(w, a) : 'Both sides differ and no successful-sync baseline exists. Change history is unknown.',
        unknownHistory: true,
      );
    }

    final wChanged = !_same(w, b);
    final aChanged = !_same(a, b);
    if (wChanged && !aChanged ||
        !wChanged && aChanged ||
        wChanged && aChanged && _same(w, a)) {
      return SyncPlanItem(
        key: key,
        title: title,
        comparison: comparison,
        classification: SyncMergeClassification.autoMergeable,
        windows: w,
        android: a,
        baseline: b,
        changedFields: fields,
        detail: 'Three-way comparison identifies one compatible final change.',
      );
    }
    if (!wChanged && !aChanged) {
      return SyncPlanItem(
        key: key,
        title: title,
        comparison: comparison,
        classification: SyncMergeClassification.same,
        windows: w,
        android: a,
        baseline: b,
      );
    }
    return SyncPlanItem(
      key: key,
      title: title,
      comparison: comparison,
      classification: SyncMergeClassification.manualConflict,
      conflictType: deleteExisting
          ? SyncConflictType.deleteModify
          : _fieldType(fields),
      windows: w,
      android: a,
      baseline: b,
      changedFields: fields,
      detail: deleteExisting ? _deleteDetail(w, a) : 'Both sides changed differently from the last successful-sync baseline.',
    );
  }

  List<SyncListConflict> _compareLists(
    SyncSnapshot w,
    SyncSnapshot a,
    SyncSnapshot? b,
  ) {
    final wm = {for (final value in w.lists) value.key: value};
    final am = {for (final value in a.lists) value.key: value};
    final bm = {
      for (final value in b?.lists ?? const <SyncList>[]) value.key: value,
    };
    final result = <SyncListConflict>[];
    for (final key in {...wm.keys, ...am.keys}.toList()..sort()) {
      final wl = wm[key]?.itemIds ?? const <String>[];
      final al = am[key]?.itemIds ?? const <String>[];
      if (_listEqual(wl, al)) continue;
      final shared = wl.where(al.toSet().contains).toSet();
      if (_listEqual(
        wl.where(shared.contains).toList(),
        al.where(shared.contains).toList(),
      )) {
        // Independent additions/removals are entity changes, not reorders.
        continue;
      }
      final bl = bm[key]?.itemIds;
      if (b != null &&
          (_listEqual(wl, bl ?? const []) || _listEqual(al, bl ?? const []))) {
        continue;
      }
      result.add(
        SyncListConflict(
          key: key,
          title: _listTitle(wm[key] ?? am[key]!),
          windowsIds: wl,
          androidIds: al,
          windowsLabels: _labels(wl, w),
          androidLabels: _labels(al, a),
          baselineIds: bl,
        ),
      );
    }
    return result;
  }

  List<SyncInvariantConflict> _invariants(SyncSnapshot w, SyncSnapshot a) {
    final result = <SyncInvariantConflict>[];
    List<SyncRecord> running(SyncSnapshot s) => s.records
        .where(
          (r) =>
              !r.isDeleted &&
              (r.kind == SyncEntityKind.event ||
                  r.kind == SyncEntityKind.routineExecution) &&
              r.payload['status'] == 'running',
        )
        .toList();
    final wr = running(w), ar = running(a);
    final runningIds = {...wr.map((r) => r.key), ...ar.map((r) => r.key)};
    if (runningIds.length > 1 && wr.isNotEmpty && ar.isNotEmpty) {
      result.add(
        SyncInvariantConflict(
          type: SyncConflictType.globalOneRunning,
          title: '运行状态冲突',
          detail: '电脑和手机分别有不同的 running 对象；合并后会违反全局最多一个 running。',
          windowsIds: wr.map((r) => r.key).toList(),
          androidIds: ar.map((r) => r.key).toList(),
        ),
      );
    }
    final openW = _openSegments(w), openA = _openSegments(a);
    if ({...openW.map((r) => r.key), ...openA.map((r) => r.key)}.length > 1 &&
        openW.isNotEmpty &&
        openA.isNotEmpty) {
      result.add(
        SyncInvariantConflict(
          type: SyncConflictType.openSegment,
          title: '开放执行片段冲突',
          detail: '合并候选包含多个 open segment。',
          windowsIds: openW.map((r) => r.key).toList(),
          androidIds: openA.map((r) => r.key).toList(),
        ),
      );
    }
    final wEntities = {
      for (final record in w.records.where(_isRunnable)) record.key: record,
    };
    final aEntities = {
      for (final record in a.records.where(_isRunnable)) record.key: record,
    };
    for (final key in wEntities.keys.where(aEntities.containsKey)) {
      final windowsEntity = wEntities[key]!;
      final androidEntity = aEntities[key]!;
      if (windowsEntity.payload['status'] == androidEntity.payload['status'] ||
          windowsEntity.payload['status'] != 'running' &&
              androidEntity.payload['status'] != 'running') {
        continue;
      }
      final id = windowsEntity.metadata.id;
      final windowsHasOpen = openW.any((segment) => _owns(segment, id));
      final androidHasOpen = openA.any((segment) => _owns(segment, id));
      if (windowsHasOpen != androidHasOpen) {
        result.add(
          SyncInvariantConflict(
            type: SyncConflictType.openSegment,
            title: '状态与执行历史冲突',
            detail: '同一对象在一端为 running 并有 open segment，另一端状态或片段已关闭。',
            windowsIds: [key],
            androidIds: [key],
          ),
        );
      }
    }
    final merged = <String, SyncRecord>{
      for (final r in w.records.where(_isSegment)) r.key: r,
      for (final r in a.records.where(_isSegment)) r.key: r,
    }.values.where((r) => !r.isDeleted).toList();
    for (var i = 0; i < merged.length; i++) {
      for (var j = i + 1; j < merged.length; j++) {
        if (_overlap(merged[i], merged[j])) {
          result.add(
            SyncInvariantConflict(
              type: SyncConflictType.segmentOverlap,
              title: '执行片段重叠',
              detail: '${merged[i].key} 与 ${merged[j].key} 在合并候选中时间重叠。',
              windowsIds: [merged[i].key],
              androidIds: [merged[j].key],
            ),
          );
        }
      }
    }
    return result;
  }

  List<SyncRecord> _openSegments(SyncSnapshot s) => s.records
      .where(
        (r) => !r.isDeleted && _isSegment(r) && r.payload['endedAtUtc'] == null,
      )
      .toList();
  bool _isSegment(SyncRecord r) =>
      r.kind == SyncEntityKind.eventRunSegment ||
      r.kind == SyncEntityKind.routineRunSegment;
  bool _isRunnable(SyncRecord r) =>
      !r.isDeleted &&
      (r.kind == SyncEntityKind.event ||
          r.kind == SyncEntityKind.routineExecution);
  bool _owns(SyncRecord segment, String id) =>
      segment.payload['eventSyncId'] == id ||
      segment.payload['routineExecutionSyncId'] == id;
  bool _overlap(SyncRecord a, SyncRecord b) {
    final startA = a.payload['startedAtUtc']! as int,
        startB = b.payload['startedAtUtc']! as int;
    final endA = a.payload['endedAtUtc'] as int? ?? 0x7fffffffffffffff,
        endB = b.payload['endedAtUtc'] as int? ?? 0x7fffffffffffffff;
    return startA < endB && startB < endA;
  }

  SyncComparisonKind _comparison(SyncRecord? w, SyncRecord? a) {
    if (w == null && a == null) return SyncComparisonKind.deletedBoth;
    if (w?.isDeleted == true && a == null) {
      return SyncComparisonKind.deletedWindows;
    }
    if (a?.isDeleted == true && w == null) {
      return SyncComparisonKind.deletedAndroid;
    }
    if (w?.isDeleted == true && a?.isDeleted == true) {
      return SyncComparisonKind.deletedBoth;
    }
    if (w?.isDeleted == true && a != null && !a.isDeleted) {
      return SyncComparisonKind.deletedWindows;
    }
    if (a?.isDeleted == true && w != null && !w.isDeleted) {
      return SyncComparisonKind.deletedAndroid;
    }
    if (w == null) return SyncComparisonKind.onlyAndroid;
    if (a == null) return SyncComparisonKind.onlyWindows;
    return _same(w, a) ? SyncComparisonKind.same : SyncComparisonKind.different;
  }

  bool _same(SyncRecord? a, SyncRecord? b) =>
      a == null && b == null ||
      a != null &&
          b != null &&
          (a.isDeleted && b.isDeleted ||
              a.entityFingerprint == b.entityFingerprint);
  bool _listEqual(List<String> a, List<String> b) =>
      a.length == b.length &&
      List.generate(a.length, (i) => a[i] == b[i]).every((v) => v);
  List<SyncFieldDiff> _fieldDiffs(
    SyncRecord? w,
    SyncRecord? a,
    SyncRecord? b,
    Map<String, SyncRecord> windows,
    Map<String, SyncRecord> android,
  ) {
    if (w == null || a == null) return const [];
    final keys = {...w.payload.keys, ...a.payload.keys}..remove('order');
    return [
      for (final key in keys.toList()..sort())
        if (w.payload[key] != a.payload[key])
          SyncFieldDiff(
            field: key,
            windowsValue: w.payload[key],
            androidValue: a.payload[key],
            baselineValue: b?.payload[key],
            windowsDisplay: _displayRelation(key, w.payload[key], windows),
            androidDisplay: _displayRelation(key, a.payload[key], android),
          ),
    ];
  }

  SyncConflictType _fieldType(List<SyncFieldDiff> fields) =>
      fields.any(
        (f) =>
            f.field == 'parentSyncId' ||
            f.field == 'parentWorldNodeSyncId' ||
            f.field == 'categorySyncId',
      )
      ? SyncConflictType.hierarchy
      : fields.isEmpty
      ? SyncConflictType.entity
      : SyncConflictType.field;
  String _deleteDetail(SyncRecord w, SyncRecord a) => w.isDeleted
      ? '电脑：已删除；手机：仍存在${a.payload.isEmpty ? '' : '且内容可能已修改'}。'
      : '手机：已删除；电脑：仍存在${w.payload.isEmpty ? '' : '且内容可能已修改'}。';
  String _title(
    SyncRecord record,
    Map<String, SyncRecord> w,
    Map<String, SyncRecord> a,
  ) {
    final name = record.payload['name'] as String?;
    if (name != null) return name;
    for (final relation in ['eventSyncId', 'routineSyncId']) {
      if (record.payload[relation] case final String id) {
        final owner = _nameFor(id, w) ?? _nameFor(id, a);
        if (owner != null) return '${record.kind.name}：$owner';
      }
    }
    return '${record.kind.name} ${record.metadata.id}';
  }

  List<String> _labels(List<String> ids, SyncSnapshot snapshot) {
    final records = {
      for (final record in snapshot.records) record.metadata.id: record,
    };
    return [
      for (final id in ids) (records[id]?.payload['name'] as String?) ?? id,
    ];
  }

  String? _displayRelation(
    String field,
    Object? value,
    Map<String, SyncRecord> records,
  ) {
    const relations = {
      'parentSyncId',
      'parentWorldNodeSyncId',
      'categorySyncId',
      'routineCategorySyncId',
      'routineSyncId',
      'eventSyncId',
      'routineExecutionSyncId',
      'legacyEventSyncId',
      'worldNodeSyncId',
    };
    if (value is! String || !relations.contains(field)) return null;
    return _nameFor(value, records) ?? value;
  }

  String? _nameFor(String id, Map<String, SyncRecord> records) {
    for (final record in records.values) {
      if (record.metadata.id == id) return record.payload['name'] as String?;
    }
    return null;
  }

  String _listTitle(SyncList list) => switch (list.kind) {
    SyncListKind.eventCategories => '世界分类顺序',
    SyncListKind.eventSiblings =>
      list.scopeId == 'root' ? '根 Event 顺序' : 'Event ${list.scopeId} 下层顺序',
    SyncListKind.routineCategories => 'Routine 分类顺序',
    SyncListKind.routines => 'Routine ${list.scopeId} 分类内顺序',
    SyncListKind.eventDayPlans => '${list.scopeId} Today 顺序',
    SyncListKind.worldNodeSiblings => 'WorldNode ${list.scopeId} 顺序',
  };
}
