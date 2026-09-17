import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/routine.dart';
import 'package:jax/core/services/routine_service.dart';
import 'package:jax/core/sync/sync_contract.dart';
import 'package:jax/core/sync/sync_mutation_plan.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';
import 'package:jax/data/sync/sqlite_sync_mutation_executor.dart';
import 'package:jax/data/sync/sqlite_sync_readiness.dart';
import 'package:jax/data/sync/sqlite_sync_snapshot_adapter.dart';

void main() {
  test('v20 migration adds only false flag, preserving all existing facts and metadata', () async {
    final dir = await Directory.systemTemp.createTemp('jax-quick-migration-');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/test.db';
    var app = await AppDatabase.open(path);
    final repo = SqliteEventRepository(app);
    var id = 0;
    final service = RoutineService(
      repository: repo,
      newId: () => '${id++}',
      now: () => DateTime(2026, 9, 5, 10),
    );
    await service.create(
      '按需',
      null,
      RoutineRecurrence.daily,
      0,
      type: RoutineType.onDemand,
    );
    await service.start((await repo.getRoutines()).single);
    await app.database.execute(
      'ALTER TABLE routines DROP COLUMN show_in_home_quick_actions',
    );
    await app.database.execute('PRAGMA user_version = 20');
    final names = (await app.database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
    )).map((r) => r['name']! as String).toList();
    final before = {
      for (final name in names) name: await app.database.query(name),
    };
    await app.close();
    app = await AppDatabase.open(path);
    try {
      expect(
        (await app.database.rawQuery('PRAGMA user_version'))
            .single
            .values
            .single,
        AppDatabase.schemaVersion,
      );
      for (final name in names) {
        final rows = [
          for (final row in await app.database.query(name))
            Map<String, Object?>.from(row),
        ];
        if (name == 'routines') {
          for (final row in rows) {
            expect(row.remove('show_in_home_quick_actions'), 0);
          }
        }
        expect(rows, before[name], reason: name);
      }
      expect(await app.database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      expect(
        (await app.database.rawQuery('PRAGMA integrity_check'))
            .single
            .values
            .single,
        'ok',
      );
      expect(await SqliteSyncReadiness(app).validate(), isEmpty);
    } finally {
      await app.close();
    }
  });

  test('flag persists, changes fingerprint, round-trips sync apply and rejects invalid values', () async {
    final app = await AppDatabase.inMemory();
    final target = await AppDatabase.inMemory();
    addTearDown(app.close);
    addTearDown(target.close);
    final repo = SqliteEventRepository(app);
    final service = RoutineService(
      repository: repo,
      newId: () => 'quick',
      now: () => DateTime(2026, 9, 5),
    );
    await service.create(
      '按需',
      null,
      RoutineRecurrence.daily,
      0,
      type: RoutineType.onDemand,
    );
    final before = await SqliteSyncSnapshotAdapter(app.database).read();
    await service.update(
      (await repo.getRoutines()).single,
      '按需',
      null,
      RoutineRecurrence.daily,
      0,
      showInHomeQuickActions: true,
    );
    final after = await SqliteSyncSnapshotAdapter(app.database).read();
    expect(after.businessFingerprint, isNot(before.businessFingerprint));
    final record = after.records.singleWhere(
      (r) => r.kind == SyncEntityKind.routine,
    );
    expect(record.payload['showInHomeQuickActions'], 1);
    await const SqliteSyncMutationExecutor().applyDatabase(target, [
      SyncMutation.upsertRecord(record),
    ]);
    expect(
      (await SqliteEventRepository(
        target,
      ).getRoutines()).single.showInHomeQuickActions,
      isTrue,
    );
    expect(await SqliteSyncReadiness(target).validate(), isEmpty);
    for (final fields in [
      {'show_in_home_quick_actions': 2},
      {'routine_type': 'scheduled'},
    ]) {
      await expectLater(
        app.database.update('routines', fields),
        throwsA(anything),
      );
    }
    final oldRecord = SyncRecord(
      kind: record.kind,
      metadata: record.metadata,
      payload: Map.of(record.payload)..remove('showInHomeQuickActions'),
    );
    final old = SyncSnapshot(
      protocolVersion: 7,
      schemaVersion: 20,
      exportedAtUtc: DateTime.utc(2026),
      records: [oldRecord],
      lists: const [],
    );
    final upgraded = SyncSnapshot.fromJsonString(old.toJsonString());
    expect(upgraded.protocolVersion, syncProtocolVersion);
    expect(upgraded.records.single.payload['showInHomeQuickActions'], 0);
    expect(upgraded.records.single.metadata.toJson(), record.metadata.toJson());
  });
}
