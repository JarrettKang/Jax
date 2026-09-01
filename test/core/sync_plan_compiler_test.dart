import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/sync/resolved_sync_plan.dart';
import 'package:jax/core/sync/sync_compare_engine.dart';
import 'package:jax/core/sync/sync_contract.dart';
import 'package:jax/core/sync/sync_mutation_plan.dart';
import 'package:jax/core/sync/sync_plan_compiler.dart';

void main() {
  const compare = SyncCompareEngine();
  const compiler = SyncPlanCompiler();

  test('unresolved conflict cannot compile', () {
    final windows = snapshot([event('a', 'PC')]);
    final android = snapshot([event('a', 'Phone')]);
    final preview = compare.compare(windows: windows, android: android);
    expect(
      () => compiler.compile(
        resolved: ResolvedSyncPlan(preview: preview),
        windows: windows,
        android: android,
      ),
      throwsA(predicate((error) => '$error'.startsWith('PLAN_NOT_RESOLVED'))),
    );
  });

  test('stale source and changed baseline are rejected', () {
    final base = snapshot([event('a', 'Base')]);
    final windows = snapshot([event('a', 'PC')]);
    final android = snapshot([event('a', 'Base')]);
    final preview = compare.compare(
      windows: windows,
      android: android,
      baseline: base,
    );
    final resolved = ResolvedSyncPlan(preview: preview);
    final stale = snapshot([event('a', 'PC'), event('new', 'New')]);
    expect(
      () => compiler.compile(
        resolved: resolved,
        windows: stale,
        android: android,
        baseline: base,
      ),
      throwsA(predicate((error) => '$error'.startsWith('STALE_SYNC_PLAN'))),
    );
    expect(
      () => compiler.compile(
        resolved: resolved,
        windows: windows,
        android: android,
        baseline: snapshot([event('a', 'Other base')]),
      ),
      throwsA(predicate((error) => '$error'.startsWith('STALE_SYNC_PLAN'))),
    );
    final incompatibleJson = preview.toJson()
      ..['syncProtocolVersion'] = syncProtocolVersion + 1;
    expect(
      () => compiler.compile(
        resolved: ResolvedSyncPlan(
          preview: SyncPlan.fromJson(incompatibleJson),
        ),
        windows: windows,
        android: android,
        baseline: base,
      ),
      throwsA(predicate((error) => '$error'.startsWith('STALE_SYNC_PLAN'))),
    );
  });

  test('resolved output and mutation plan are deterministic', () {
    final windows = snapshot(
      [event('a', 'PC'), event('b', 'B')],
    );
    final android = snapshot(
      [event('a', 'Phone'), event('b', 'B'), event('c', 'C')],
    );
    final preview = compare.compare(windows: windows, android: android);
    final resolved = ResolvedSyncPlan(
      preview: preview,
      recordChoices: {'event:a': SyncSide.windows},
    );
    final first = compiler.compile(
      resolved: resolved,
      windows: windows,
      android: android,
    );
    final second = compiler.compile(
      resolved: resolved,
      windows: windows,
      android: android,
    );
    expect(jsonEncode(first.toJson()), jsonEncode(second.toJson()));
    expect(
      first.expectedFinalSnapshot.records
          .where((r) => !r.isDeleted)
          .map((r) => r.metadata.id),
      ['a', 'b', 'c'],
    );
    expect(first.expectedFinalSnapshot.lists, isEmpty);
    final decodedResolution = ResolvedSyncPlan.fromResolutionJson(
      preview,
      resolved.toResolutionJson(),
    );
    final roundTrip = compiler.compile(
      resolved: decodedResolution,
      windows: windows,
      android: android,
    );
    expect(jsonEncode(roundTrip.toJson()), jsonEncode(first.toJson()));
    expect(
      jsonEncode(SyncMutationPlan.fromJson(first.toJson()).toJson()),
      jsonEncode(first.toJson()),
    );
  });

  test('invalid explicit invariant override is rejected before mutation', () {
    final windows = snapshot([
      event('a', 'A', status: 'running'),
      segment('sa', 'a'),
    ]);
    final android = snapshot([
      event('b', 'B', status: 'running'),
      segment('sb', 'b'),
    ]);
    final preview = compare.compare(windows: windows, android: android);
    final resolutions = {
      for (final conflict in preview.invariantConflicts)
        conflict.key: const SyncInvariantResolution(recordOverrides: {}),
    };
    expect(
      () => compiler.compile(
        resolved: ResolvedSyncPlan(
          preview: preview,
          invariantResolutions: resolutions,
        ),
        windows: windows,
        android: android,
      ),
      throwsA(predicate((error) => '$error'.startsWith('PLAN_INVALID'))),
    );
  });

  test('invariant override cannot introduce an unanalyzed identity', () {
    final windows = snapshot([
      event('a', 'A', status: 'running'),
      segment('sa', 'a'),
    ]);
    final android = snapshot([
      event('b', 'B', status: 'running'),
      segment('sb', 'b'),
    ]);
    final preview = compare.compare(windows: windows, android: android);
    expect(
      () => compiler.compile(
        resolved: ResolvedSyncPlan(
          preview: preview,
          invariantResolutions: {
            for (final conflict in preview.invariantConflicts)
              conflict.key: SyncInvariantResolution(
                recordOverrides: {'event:injected': event('injected', 'X')},
              ),
          },
        ),
        windows: windows,
        android: android,
      ),
      throwsA(predicate((error) => '$error'.startsWith('PLAN_INVALID'))),
    );
  });

  test('explicit running resolution produces one legal running owner', () {
    final windows = snapshot([
      event('a', 'A', status: 'running'),
      segment('sa', 'a'),
    ]);
    final android = snapshot([
      event('b', 'B', status: 'running'),
      segment('sb', 'b'),
    ]);
    final preview = compare.compare(windows: windows, android: android);
    final resolution = SyncInvariantResolution(
      recordOverrides: {
        'event:b': event('b', 'B', status: 'paused'),
        'eventRunSegment:sb': segment(
          'sb',
          'b',
          startedAtUtc: 1,
          endedAtUtc: 5,
        ),
      },
    );
    final plan = compiler.compile(
      resolved: ResolvedSyncPlan(
        preview: preview,
        invariantResolutions: {
          for (final conflict in preview.invariantConflicts)
            conflict.key: resolution,
        },
      ),
      windows: windows,
      android: android,
    );

    expect(
      plan.expectedFinalSnapshot.records
          .where((record) => record.payload['status'] == 'running')
          .map((record) => record.metadata.id),
      ['a'],
    );
    expect(
      plan.expectedFinalSnapshot.records
          .singleWhere((record) => record.metadata.id == 'sb')
          .payload['endedAtUtc'],
      5,
    );
  });

  test(
    'segment conflict resolution keeps the explicitly selected interval',
    () {
      final windows = snapshot([
        event('a', 'A'),
        segment('s', 'a', startedAtUtc: 10, endedAtUtc: 20),
      ]);
      final android = snapshot([
        event('a', 'A'),
        segment('s', 'a', startedAtUtc: 12, endedAtUtc: 25),
      ]);
      final preview = compare.compare(windows: windows, android: android);
      final plan = compiler.compile(
        resolved: ResolvedSyncPlan(
          preview: preview,
          recordChoices: {'eventRunSegment:s': SyncSide.windows},
        ),
        windows: windows,
        android: android,
      );

      final selected = plan.expectedFinalSnapshot.records.singleWhere(
        (record) => record.metadata.id == 's',
      );
      expect(selected.payload['startedAtUtc'], 10);
      expect(selected.payload['endedAtUtc'], 20);
    },
  );

}

final instant = DateTime.fromMillisecondsSinceEpoch(100, isUtc: true);
SyncSnapshot snapshot(
  List<SyncRecord> records, {
  List<SyncList> lists = const [],
}) => SyncSnapshot(
  schemaVersion: 16,
  exportedAtUtc: instant,
  records: records,
  lists: lists,
);
SyncRecord event(
  String id,
  String name, {
  String status = 'paused',
}) => SyncRecord(
  kind: SyncEntityKind.event,
  metadata: SyncMetadata(id: id, createdAtUtc: instant, updatedAtUtc: instant),
  payload: {
    'name': name,
    'status': status,
    'sourcePlanItemSyncId': null,
    'categorySyncId': null,
    'order': 0,
    'firstStartedAtUtc': null,
    'completedAtUtc': null,
  },
);
SyncRecord segment(
  String id,
  String owner, {
  int startedAtUtc = 10,
  int? endedAtUtc,
}) => SyncRecord(
  kind: SyncEntityKind.eventRunSegment,
  metadata: SyncMetadata(id: id, createdAtUtc: instant, updatedAtUtc: instant),
  payload: {
    'eventSyncId': owner,
    'startedAtUtc': startedAtUtc,
    'endedAtUtc': endedAtUtc,
  },
);
