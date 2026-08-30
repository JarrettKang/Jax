import 'dart:io';

import '../../core/sync/sync_contract.dart';
import 'sync_apply_orchestrator.dart';

class FileSyncBaselineStore implements SyncBaselineStore {
  const FileSyncBaselineStore(this.path);

  final String path;

  Future<SyncSnapshot?> read() async {
    final file = File(path);
    if (!await file.exists()) return null;
    return SyncSnapshot.fromJsonString(await file.readAsString());
  }

  @override
  Future<void> writeSuccessfulBaseline(SyncSnapshot snapshot) async {
    final output = File(path);
    await output.parent.create(recursive: true);
    final staged = File('$path.pending');
    if (await staged.exists()) await staged.delete();
    await staged.writeAsString(
      snapshot.toJsonString(pretty: true),
      flush: true,
    );
    final parsed = SyncSnapshot.fromJsonString(await staged.readAsString());
    if (parsed.businessFingerprintSha256 !=
        snapshot.businessFingerprintSha256) {
      throw StateError('Staged baseline fingerprint verification failed.');
    }
    if (await output.exists()) {
      final previous = File('$path.previous');
      if (await previous.exists()) await previous.delete();
      await output.rename(previous.path);
      try {
        await staged.rename(path);
      } catch (_) {
        await previous.rename(path);
        rethrow;
      }
      await previous.delete();
    } else {
      await staged.rename(path);
    }
    final persisted = await read();
    if (persisted?.businessFingerprintSha256 !=
        snapshot.businessFingerprintSha256) {
      throw StateError('Persisted baseline fingerprint verification failed.');
    }
  }
}
