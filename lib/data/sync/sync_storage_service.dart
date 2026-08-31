import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'file_sync_baseline_store.dart';
import 'sqlite_sync_snapshot_adapter.dart';

class SyncStorageSettings {
  const SyncStorageSettings({
    required this.root,
    required this.layoutVersion,
    required this.backupRetention,
  });
  final String root;
  final int layoutVersion;
  final int backupRetention;

  bool get legacyLayout => layoutVersion == 0;
  String get baselinePath => legacyLayout
      ? '$root${Platform.pathSeparator}sync${Platform.pathSeparator}last_successful_sync.json'
      : '$root${Platform.pathSeparator}baseline${Platform.pathSeparator}last_successful_sync.json';
  String get backupsPath => legacyLayout
      ? '$root${Platform.pathSeparator}sync_backups'
      : '$root${Platform.pathSeparator}backups';
  String get sessionsPath => '$root${Platform.pathSeparator}sessions';
  String get logsPath => '$root${Platform.pathSeparator}logs';

  Map<String, Object?> toJson() => {
    'version': 1,
    'root': root,
    'layoutVersion': layoutVersion,
    'backupRetention': backupRetention,
  };
}

class SyncStorageInventory {
  const SyncStorageInventory({
    required this.baselineExists,
    required this.backupSessions,
    required this.totalBytes,
  });
  final bool baselineExists;
  final int backupSessions;
  final int totalBytes;
}

class SyncStorageMigrationResult {
  const SyncStorageMigrationResult({
    required this.settings,
    required this.baselineFingerprint,
    required this.removedOldCopies,
  });
  final SyncStorageSettings settings;
  final String? baselineFingerprint;
  final bool removedOldCopies;
}

class SyncStorageService {
  SyncStorageService({String? appDataRoot, this.copyInterceptor})
    : appDataRoot = appDataRoot ?? Platform.environment['APPDATA']!;

  final String appDataRoot;
  @visibleForTesting
  final Future<void> Function(String source, String destination)?
  copyInterceptor;
  String get _jaxRoot => '$appDataRoot${Platform.pathSeparator}Jax';
  String get configPath =>
      '$_jaxRoot${Platform.pathSeparator}sync_storage.json';

  Future<SyncStorageSettings> load() async {
    final file = File(configPath);
    if (!await file.exists()) {
      return SyncStorageSettings(
        root: _jaxRoot,
        layoutVersion: 0,
        backupRetention: 5,
      );
    }
    final json = (jsonDecode(await file.readAsString()) as Map)
        .cast<String, Object?>();
    return SyncStorageSettings(
      root: json['root']! as String,
      layoutVersion: (json['layoutVersion'] as num?)?.toInt() ?? 1,
      backupRetention: ((json['backupRetention'] as num?)?.toInt() ?? 5).clamp(
        1,
        50,
      ),
    );
  }

  Future<SyncStorageInventory> inventory(SyncStorageSettings settings) async {
    var bytes = 0;
    Future<void> addTree(String path) async {
      final directory = Directory(path);
      if (!await directory.exists()) return;
      await for (final entity in directory.list(recursive: true)) {
        if (entity is File) bytes += await entity.length();
      }
    }

    await addTree(
      settings.legacyLayout
          ? '${settings.root}${Platform.pathSeparator}sync'
          : '${settings.root}${Platform.pathSeparator}baseline',
    );
    await addTree(settings.backupsPath);
    await addTree(settings.sessionsPath);
    await addTree(settings.logsPath);
    final backups = Directory(settings.backupsPath);
    return SyncStorageInventory(
      baselineExists: await File(settings.baselinePath).exists(),
      backupSessions: await backups.exists()
          ? await backups.list().where((entity) => entity is Directory).length
          : 0,
      totalBytes: bytes,
    );
  }

  Future<void> updateRetention(int count) async {
    final current = await load();
    await _persist(
      SyncStorageSettings(
        root: current.root,
        layoutVersion: current.layoutVersion,
        backupRetention: count.clamp(1, 50),
      ),
    );
  }

  Future<List<String>> cleanupBackups({String? activeSessionPath}) async {
    final settings = await load();
    final root = Directory(settings.backupsPath);
    if (!await root.exists()) return const [];
    final sessions = await root
        .list()
        .where((e) => e is Directory)
        .cast<Directory>()
        .toList();
    sessions.sort((a, b) => b.path.compareTo(a.path));
    final removable = <Directory>[];
    var retainedNormal = 0;
    for (final session in sessions) {
      if (session.absolute.path == activeSessionPath) continue;
      final metadata = File(
        '${session.path}${Platform.pathSeparator}metadata.json',
      );
      String? status;
      if (await metadata.exists()) {
        try {
          status = (jsonDecode(await metadata.readAsString()) as Map)['status']
              ?.toString();
        } catch (_) {}
      }
      if (status == 'CRITICAL_ROLLBACK_FAILURE') continue;
      if (retainedNormal++ >= settings.backupRetention) removable.add(session);
    }
    final removed = <String>[];
    for (final session in removable) {
      await session.delete(recursive: true);
      removed.add(session.path);
    }
    return removed;
  }

  Future<SyncStorageMigrationResult> migrate(String destination) async {
    final source = await load();
    final normalized = Directory(destination).absolute.path;
    final sourceRoot = Directory(source.root).absolute.path;
    if (_sameOrNested(normalized, sourceRoot) ||
        _sameOrNested(sourceRoot, normalized)) {
      throw ArgumentError('新位置不能与当前位置相同，也不能互相嵌套。');
    }
    final target = SyncStorageSettings(
      root: normalized,
      layoutVersion: 1,
      backupRetention: source.backupRetention,
    );
    final destinationDirectory = Directory(normalized);
    await destinationDirectory.create(recursive: true);
    final probe = File('$normalized${Platform.pathSeparator}.jax_write_probe');
    try {
      await probe.writeAsString('jax-sync', flush: true);
      await probe.delete();
    } catch (error) {
      throw FileSystemException('目标目录不可写：$error', normalized);
    }
    for (final name in ['baseline', 'backups', 'sessions', 'logs']) {
      final candidate = Directory('$normalized${Platform.pathSeparator}$name');
      if (await candidate.exists() && !(await candidate.list().isEmpty)) {
        throw FileSystemException('目标同步目录不是空目录。', candidate.path);
      }
    }

    final oldBaseline = await FileSyncBaselineStore(source.baselinePath).read();
    var switched = false;
    try {
      await _copyFileIfPresent(source.baselinePath, target.baselinePath);
      await _copyDirectory(source.backupsPath, target.backupsPath);
      await _copyDirectory(source.sessionsPath, target.sessionsPath);
      await _copyDirectory(source.logsPath, target.logsPath);
      final newBaseline = await FileSyncBaselineStore(target.baselinePath)
          .read();
      if (oldBaseline?.businessFingerprintSha256 !=
          newBaseline?.businessFingerprintSha256) {
        throw StateError('迁移后的 baseline fingerprint 不一致。');
      }
      final backups = Directory(target.backupsPath);
      if (await backups.exists()) {
        await for (final entity in backups.list(recursive: true)) {
          if (entity is File && entity.path.toLowerCase().endsWith('.db')) {
            sqfliteFfiInit();
            final database = await databaseFactoryFfi.openDatabase(
              entity.path,
              options: OpenDatabaseOptions(readOnly: true),
            );
            try {
              await SqliteSyncSnapshotAdapter(database).read();
            } finally {
              await database.close();
            }
          }
        }
      }
      await _persist(target);
      switched = true;
      final reopened = await FileSyncBaselineStore((await load()).baselinePath)
          .read();
      if (reopened?.businessFingerprintSha256 !=
          oldBaseline?.businessFingerprintSha256) {
        throw StateError('切换后无法重新读取原 baseline。');
      }
      var removed = true;
      try {
        await _deleteOldData(source);
      } catch (_) {
        removed = false;
      }
      return SyncStorageMigrationResult(
        settings: target,
        baselineFingerprint: reopened?.businessFingerprintSha256,
        removedOldCopies: removed,
      );
    } catch (error) {
      if (switched) {
        try {
          await _persist(source);
        } catch (rollbackError) {
          throw StateError(
            '迁移验证失败，且无法恢复原存储配置。'
            '新位置数据已保留，未执行清理。'
            ' error=$error; rollback=$rollbackError',
          );
        }
      }
      await _deleteTargetData(target);
      rethrow;
    }
  }

  Future<void> _persist(SyncStorageSettings settings) async {
    final file = File(configPath);
    await file.parent.create(recursive: true);
    final staged = File('${file.path}.pending');
    final previous = File('${file.path}.previous');
    if (await staged.exists()) await staged.delete();
    if (await previous.exists()) await previous.delete();
    await staged.writeAsString(
      const JsonEncoder.withIndent('  ').convert(settings.toJson()),
      flush: true,
    );
    final hadCurrent = await file.exists();
    if (hadCurrent) await file.rename(previous.path);
    try {
      await staged.rename(file.path);
      final reread = await load();
      if (reread.root != settings.root ||
          reread.layoutVersion != settings.layoutVersion ||
          reread.backupRetention != settings.backupRetention) {
        throw StateError('同步存储配置验证失败。');
      }
      if (await previous.exists()) await previous.delete();
    } catch (_) {
      if (await file.exists()) await file.delete();
      if (hadCurrent && await previous.exists()) {
        await previous.rename(file.path);
      }
      rethrow;
    } finally {
      if (await staged.exists()) await staged.delete();
    }
  }

  Future<void> _copyFileIfPresent(String source, String destination) async {
    final file = File(source);
    if (!await file.exists()) return;
    await copyInterceptor?.call(source, destination);
    final target = File(destination);
    await target.parent.create(recursive: true);
    await file.copy(target.path);
    if (await file.length() != await target.length()) {
      throw StateError('复制文件长度验证失败：$source');
    }
    final sourceDigest = await sha256.bind(file.openRead()).first;
    final targetDigest = await sha256.bind(target.openRead()).first;
    if (sourceDigest != targetDigest) {
      throw StateError('复制文件内容验证失败：$source');
    }
  }

  Future<void> _copyDirectory(String source, String destination) async {
    final directory = Directory(source);
    if (!await directory.exists()) return;
    await for (final entity in directory.list(recursive: true)) {
      if (entity is! File) continue;
      final relative = entity.path.substring(directory.path.length + 1);
      await _copyFileIfPresent(
        entity.path,
        '$destination${Platform.pathSeparator}$relative',
      );
    }
  }

  Future<void> _deleteOldData(SyncStorageSettings source) async {
    final paths = source.legacyLayout
        ? [
            '${source.root}${Platform.pathSeparator}sync',
            source.backupsPath,
            source.sessionsPath,
            source.logsPath,
          ]
        : [
            '${source.root}${Platform.pathSeparator}baseline',
            source.backupsPath,
            source.sessionsPath,
            source.logsPath,
          ];
    for (final path in paths.toSet()) {
      final directory = Directory(path);
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  }

  Future<void> _deleteTargetData(SyncStorageSettings target) async {
    for (final path in [
      '${target.root}${Platform.pathSeparator}baseline',
      target.backupsPath,
      target.sessionsPath,
      target.logsPath,
    ]) {
      final directory = Directory(path);
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  }

  bool _sameOrNested(String candidate, String parent) {
    String normalize(String value) {
      final result = value.replaceAll('/', Platform.pathSeparator);
      return Platform.isWindows ? result.toLowerCase() : result;
    }

    final child = normalize(candidate);
    final root = normalize(parent);
    return child == root || child.startsWith('$root${Platform.pathSeparator}');
  }
}
