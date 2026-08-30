import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/sync/sync_contract.dart';
import 'package:jax/data/sync/file_sync_baseline_store.dart';

void main() {
  test(
    'successful baseline persists and reloads with the same fingerprint',
    () async {
      final root = await Directory.systemTemp.createTemp('jax-baseline-');
      addTearDown(() => root.delete(recursive: true));
      final path = '${root.path}${Platform.pathSeparator}last.json';
      final store = FileSyncBaselineStore(path);
      final snapshot = SyncSnapshot(
        schemaVersion: 13,
        exportedAtUtc: DateTime.fromMillisecondsSinceEpoch(100, isUtc: true),
        records: const [],
        lists: const [],
      );

      expect(await store.read(), isNull);
      await store.writeSuccessfulBaseline(snapshot);
      final reopened = await FileSyncBaselineStore(path).read();

      expect(
        reopened?.businessFingerprintSha256,
        snapshot.businessFingerprintSha256,
      );
      expect(File('$path.pending').existsSync(), isFalse);
      expect(File('$path.previous').existsSync(), isFalse);
    },
  );
}
