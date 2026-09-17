import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// An ownership marker is an accidental-deletion guard, not authentication.
Future<bool> isOwnedBackup(String root, String directory) async {
  try {
    final full = p.normalize(p.absolute(directory));
    final parent = p.normalize(p.absolute(root));
    if (!p.equals(p.dirname(full), parent) || p.equals(full, parent)) {
      return false;
    }
    var cursor = full;
    while (true) {
      if (FileSystemEntity.typeSync(cursor, followLinks: false) ==
          FileSystemEntityType.link) {
        return false;
      }
      final next = p.dirname(cursor);
      if (next == cursor) break;
      cursor = next;
    }
    if (!p.equals(await Directory(full).resolveSymbolicLinks(), full)) {
      return false;
    }
    await for (final entry in Directory(
      full,
    ).list(recursive: true, followLinks: false)) {
      if (entry is Link) return false;
    }
    final id = p.basename(full);
    if (!RegExp(r'^\d{8}_\d{6}_[a-f0-9]{32}$').hasMatch(id)) return false;
    final metadata = jsonDecode(
      await File(p.join(full, 'metadata.json')).readAsString(),
    ) as Map;
    return metadata['owner'] == 'jax-sync-backup' &&
        metadata['metadataVersion'] == 1 &&
        metadata['sessionId'] == id &&
        metadata['schemaVersion'] is int &&
        (metadata['schemaVersion'] as int) > 0 &&
        metadata['protocolVersion'] is int &&
        (metadata['protocolVersion'] as int) > 0 &&
        DateTime.tryParse(metadata['createdAtUtc'] as String) != null &&
        const [
          'Success',
          'SYNC_SUCCEEDED',
          'SYNC_FAILED_ROLLED_BACK',
          'SYNC_APPLIED_BASELINE_WRITE_FAILED',
          'CRITICAL_ROLLBACK_FAILURE',
        ].contains(metadata['status']);
  } catch (_) {
    return false;
  }
}
