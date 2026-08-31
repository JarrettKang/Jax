import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/sync/sync_compare_engine.dart';
import 'package:jax/core/sync/sync_contract.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/sync/file_sync_baseline_store.dart';
import 'package:jax/data/sync/sync_storage_service.dart';

void main() {
  test(
    'default storage keeps legacy baseline and defaults retention to five',
    () async {
      final root = await _temporary('default');
      final service = SyncStorageService(appDataRoot: root.path);
      final settings = await service.load();
      final snapshot = _snapshot();
      await FileSyncBaselineStore(settings.baselinePath)
          .writeSuccessfulBaseline(snapshot);
      final reopened = await FileSyncBaselineStore(
        (await service.load()).baselinePath,
      ).read();
      expect(settings.legacyLayout, isTrue);
      expect(settings.backupRetention, 5);
      expect(
        reopened?.businessFingerprintSha256,
        snapshot.businessFingerprintSha256,
      );
    },
  );

  test('fresh custom root supports baseline and backup read/write', () async {
    final root = await _temporary('custom-source');
    final destination = await _temporary('custom-destination');
    final service = SyncStorageService(appDataRoot: root.path);
    await service.migrate(destination.path);
    final settings = await service.load();
    final snapshot = _snapshot();
    await FileSyncBaselineStore(settings.baselinePath)
        .writeSuccessfulBaseline(snapshot);
    final backup =
        '${settings.backupsPath}${Platform.pathSeparator}session'
        '${Platform.pathSeparator}windows_before_sync.db';
    final database = await AppDatabase.open(backup);
    await database.database.close();
    final reopened = await AppDatabase.open(backup);
    await reopened.database.close();
    expect(
      (await FileSyncBaselineStore(
        settings.baselinePath,
      ).read())?.businessFingerprintSha256,
      snapshot.businessFingerprintSha256,
    );
    expect(File(backup).existsSync(), isTrue);
  });

  test('baseline-only migration remains a three-way comparison', () async {
    final root = await _temporary('baseline-only');
    final destination = await _temporary('baseline-only-destination');
    final service = SyncStorageService(appDataRoot: root.path);
    final old = await service.load();
    final baseline = _snapshot();
    await FileSyncBaselineStore(old.baselinePath)
        .writeSuccessfulBaseline(baseline);
    final result = await service.migrate(destination.path);
    final migrated = await FileSyncBaselineStore(result.settings.baselinePath)
        .read();
    final plan = const SyncCompareEngine().compare(
      windows: baseline,
      android: baseline,
      baseline: migrated,
    );
    expect(
      migrated?.businessFingerprintSha256,
      baseline.businessFingerprintSha256,
    );
    expect(plan.hasBaseline, isTrue);
  });

  test(
    'safe migration preserves baseline fingerprint and verifies both backups',
    () async {
      final root = await _temporary('migration');
      final destination = await _temporary('destination');
      final service = SyncStorageService(appDataRoot: root.path);
      final old = await service.load();
      final snapshot = _snapshot();
      await FileSyncBaselineStore(old.baselinePath)
          .writeSuccessfulBaseline(snapshot);
      final session = Directory(
        '${old.backupsPath}${Platform.pathSeparator}20260831_100000',
      )..createSync(recursive: true);
      for (final name in ['windows_before_sync.db', 'android_before_sync.db']) {
        final database = await AppDatabase.open(
          '${session.path}${Platform.pathSeparator}$name',
        );
        await database.database.close();
      }
      final result = await service.migrate(destination.path);
      final current = await service.load();
      expect(current.root, destination.absolute.path);
      expect(current.legacyLayout, isFalse);
      expect(result.baselineFingerprint, snapshot.businessFingerprintSha256);
      expect(
        await FileSyncBaselineStore(current.baselinePath).read(),
        isNotNull,
      );
      expect(
        Directory(current.backupsPath)
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.db'))
            .length,
        2,
      );
      expect(Directory(old.backupsPath).existsSync(), isFalse);
    },
  );

  test('verify failure keeps old root and baseline usable', () async {
    final root = await _temporary('rollback');
    final destination = await _temporary('bad_destination');
    final service = SyncStorageService(appDataRoot: root.path);
    final old = await service.load();
    final snapshot = _snapshot();
    await FileSyncBaselineStore(old.baselinePath)
        .writeSuccessfulBaseline(snapshot);
    final session = Directory(
      '${old.backupsPath}${Platform.pathSeparator}broken',
    )..createSync(recursive: true);
    File('${session.path}${Platform.pathSeparator}windows_before_sync.db')
        .writeAsStringSync('not sqlite');
    await expectLater(service.migrate(destination.path), throwsA(anything));
    final current = await service.load();
    expect(current.root, old.root);
    expect(
      (await FileSyncBaselineStore(
        current.baselinePath,
      ).read())?.businessFingerprintSha256,
      snapshot.businessFingerprintSha256,
    );
    expect(
      File('${session.path}${Platform.pathSeparator}windows_before_sync.db')
          .existsSync(),
      isTrue,
    );
  });

  test('copy failure rolls back and leaves old root usable', () async {
    final root = await _temporary('copy-failure');
    final destination = await _temporary('copy-failure-destination');
    var failed = false;
    final service = SyncStorageService(
      appDataRoot: root.path,
      copyInterceptor: (source, destination) async {
        if (!failed) {
          failed = true;
          throw const FileSystemException('injected copy failure');
        }
      },
    );
    final old = await service.load();
    final snapshot = _snapshot();
    await FileSyncBaselineStore(old.baselinePath)
        .writeSuccessfulBaseline(snapshot);
    await expectLater(service.migrate(destination.path), throwsA(anything));
    final current = await service.load();
    expect(current.root, old.root);
    expect(
      (await FileSyncBaselineStore(
        current.baselinePath,
      ).read())?.businessFingerprintSha256,
      snapshot.businessFingerprintSha256,
    );
  });

  test('invalid destination does not switch configuration', () async {
    final root = await _temporary('invalid');
    final service = SyncStorageService(appDataRoot: root.path);
    final old = await service.load();
    final invalid = File('${root.path}${Platform.pathSeparator}not_a_directory')
      ..writeAsStringSync('x');
    await expectLater(service.migrate(invalid.path), throwsA(anything));
    expect((await service.load()).root, old.root);
  });

  test(
    'retention removes whole old sessions and protects active and critical',
    () async {
      final root = await _temporary('retention');
      final jax = Directory('${root.path}${Platform.pathSeparator}Jax')
        ..createSync();
      final storage = Directory('${root.path}${Platform.pathSeparator}custom')
        ..createSync();
      File('${jax.path}${Platform.pathSeparator}sync_storage.json')
          .writeAsStringSync(
            jsonEncode({
              'version': 1,
              'root': storage.path,
              'layoutVersion': 1,
              'backupRetention': 1,
            }),
          );
      final service = SyncStorageService(appDataRoot: root.path);
      final settings = await service.load();
      Directory session(String name, {String? status}) {
        final directory = Directory(
          '${settings.backupsPath}${Platform.pathSeparator}$name',
        )..createSync(recursive: true);
        File('${directory.path}${Platform.pathSeparator}windows.db')
            .writeAsStringSync('w');
        File('${directory.path}${Platform.pathSeparator}android.db')
            .writeAsStringSync('a');
        if (status != null) {
          File('${directory.path}${Platform.pathSeparator}metadata.json')
              .writeAsStringSync(jsonEncode({'status': status}));
        }
        return directory;
      }

      final newest = session('20260831_3', status: 'SYNC_FAILED_ROLLED_BACK');
      final active = session('20260831_2');
      final critical = session(
        '20260831_1',
        status: 'CRITICAL_ROLLBACK_FAILURE',
      );
      final old = session('20260831_0');
      final removed = await service.cleanupBackups(
        activeSessionPath: active.absolute.path,
      );
      expect(newest.existsSync(), isTrue);
      expect(active.existsSync(), isTrue);
      expect(critical.existsSync(), isTrue);
      expect(old.existsSync(), isFalse);
      expect(removed, [old.path]);
    },
  );

  test('retention does not delete one session or exactly N sessions', () async {
    final root = await _temporary('retention-boundaries');
    final jax = Directory('${root.path}${Platform.pathSeparator}Jax')
      ..createSync();
    final storage = Directory('${root.path}${Platform.pathSeparator}custom')
      ..createSync();
    File('${jax.path}${Platform.pathSeparator}sync_storage.json')
        .writeAsStringSync(
          jsonEncode({
            'version': 1,
            'root': storage.path,
            'layoutVersion': 1,
            'backupRetention': 3,
          }),
        );
    final service = SyncStorageService(appDataRoot: root.path);
    final settings = await service.load();
    for (final name in ['1', '2', '3']) {
      final session = Directory(
        '${settings.backupsPath}${Platform.pathSeparator}$name',
      )..createSync(recursive: true);
      File('${session.path}${Platform.pathSeparator}windows.db')
          .writeAsStringSync(name);
      File('${session.path}${Platform.pathSeparator}android.db')
          .writeAsStringSync(name);
    }
    expect(await service.cleanupBackups(), isEmpty);
    expect(Directory(settings.backupsPath).listSync().length, 3);
  });
}

Future<Directory> _temporary(String name) async {
  final directory = await Directory.systemTemp.createTemp('jax-storage-$name-');
  addTearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });
  return directory;
}

SyncSnapshot _snapshot() {
  final instant = DateTime.fromMillisecondsSinceEpoch(1, isUtc: true);
  return SyncSnapshot(
    schemaVersion: 13,
    exportedAtUtc: instant,
    records: [
      SyncRecord(
        kind: SyncEntityKind.event,
        metadata: SyncMetadata(
          id: 'event',
          createdAtUtc: instant,
          updatedAtUtc: instant,
        ),
        payload: const {'name': '检查超算', 'status': 'pending'},
      ),
    ],
    lists: const [],
  );
}
