import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/database/development_data_reset.dart';
import 'package:jax/data/sync/backup_ownership.dart';
import 'package:jax/data/sync/sync_storage_service.dart';
import 'package:jax/data/sync/windows_debug_sync_coordinator.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../tool/development_data_reset.dart' as reset;
import '../../tool/create_development_fixture.dart' as creator;
import '../../tool/database_snapshot.dart' as snapshot;
import '../../tool/sync_readiness.dart' as readiness;
import '../../tool/world_node_migration_report.dart' as migration;
import '../../tool/private_tool_support.dart';

void main() {
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('jax-tool-safety-');
  });
  tearDown(() async {
    await temp.delete(recursive: true);
  });

  Future<String> fixture() async {
    final file = p.join(temp.path, 'fixture.db');
    final app = await AppDatabase.open(file);
    await DevelopmentDataReset(app).run(generation: 'fixture-before');
    await app.database.insert('categories', {
      'id': 'category',
      'name': 'Synthetic',
      'sort_order': 0,
      'color_key': 0,
      'created_at_utc': 1,
      'updated_at_utc': 1,
    });
    await app.close();
    await File('$file.jax-fixture.json').writeAsString(
      jsonEncode({
        'owner': 'jax-development-fixture',
        'version': 1,
        'databaseName': 'fixture.db',
      }),
    );
    return file;
  }

  test(
    'relative fixture and snapshot paths resolve against the caller directory',
    () async {
      final privateRoot = Directory(
        p.join(Directory.current.path, '.local_private'),
      );
      await privateRoot.create(recursive: true);
      final relativeTemp = await privateRoot.createTemp('relative-tool-test-');
      addTearDown(() async {
        expect(
          p.isWithin(privateRoot.absolute.path, relativeTemp.absolute.path),
          isTrue,
        );
        await relativeTemp.delete(recursive: true);
      });
      final file = p.join(relativeTemp.path, 'relative.db');
      final relative = p.relative(file, from: Directory.current.path);
      expect(p.isRelative(relative), isTrue);
      await creator.runCreateFixture([relative]);
      expect(File(file).existsSync(), isTrue);
      expect(File('$file.jax-fixture.json').existsSync(), isTrue);
      await expectLater(creator.runCreateFixture([relative]), throwsStateError);
      final db = await openReadOnly(relative);
      expect(
        (await db.query('dataset_metadata')).single['generation'],
        startsWith('fixture-'),
      );
      await db.close();
      final output = p.relative(
        p.join(relativeTemp.path, 'snapshot.db'),
        from: Directory.current.path,
      );
      await snapshot.runSnapshot(['snapshot', relative, output]);
      await snapshot.runSnapshot(['verify', output]);
      await reset.runReset([
        relative,
        'fixture-next',
        '--apply',
        '--confirm-destructive-reset',
      ]);
      if (Platform.environment['APPDATA'] case final String appData) {
        await expectLater(
          creator.runCreateFixture([p.join(appData, 'Jax', 'new-fixture.db')]),
          throwsStateError,
        );
      }
    },
  );

  test('reset defaults to no writes; dual confirmation resets after verified backup', () async {
    final file = await fixture();
    final before = await File(file).readAsBytes();
    await reset.runReset([file, 'fixture-after']);
    expect(await File(file).readAsBytes(), before);
    await reset.runReset([file, 'fixture-after', '--apply']);
    expect(await File(file).readAsBytes(), before);
    await reset.runReset([
      file,
      'fixture-after',
      '--apply',
      '--confirm-destructive-reset',
    ]);
    final db = await openReadOnly(file);
    expect(await db.query('categories'), isEmpty);
    await db.close();
    final backups = Directory(p.join(temp.path, '.local_private', 'backups'))
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.db'))
        .toList();
    expect(backups, hasLength(1));
    final backup = await openReadOnly(backups.single.path);
    expect(await backup.query('categories'), hasLength(1));
    await backup.close();
  });

  test(
    'reset refuses unmarked data, real path, invalid schema and backup failure',
    () async {
      final file = await fixture();
      final before = await File(file).readAsBytes();
      await File('$file.jax-fixture.json').rename('$file.marker');
      await expectLater(
        reset.runReset([
          file,
          'fixture-new',
          '--apply',
          '--confirm-destructive-reset',
        ]),
        throwsA(anything),
      );
      await File('$file.marker').rename('$file.jax-fixture.json');
      await File(p.join(temp.path, '.local_private'))
          .writeAsString('blocked backup root');
      await expectLater(
        reset.runReset([
          file,
          'fixture-new',
          '--apply',
          '--confirm-destructive-reset',
        ]),
        throwsA(anything),
      );
      expect(await File(file).readAsBytes(), before);
      if (Platform.environment['APPDATA'] case final String appData) {
        await expectLater(
          reset.runReset([
            p.join(appData, 'Jax', 'jax.db'),
            'fixture-new',
            '--apply',
            '--confirm-destructive-reset',
          ]),
          throwsA(isA<StateError>()),
        );
      }
      final db = await databaseFactoryFfi.openDatabase(file);
      await db.execute('PRAGMA user_version = 1');
      await db.close();
      final old = await File(file).readAsBytes();
      await expectLater(
        reset.runReset([
          file,
          'fixture-new',
          '--apply',
          '--confirm-destructive-reset',
        ]),
        throwsA(anything),
      );
      await expectLater(readiness.runAudit([file]), throwsA(anything));
      await expectLater(migration.runAudit([file]), throwsA(anything));
      expect(await File(file).readAsBytes(), old);
    },
  );

  test(
    'snapshot uses current schema and never overwrites source or destination',
    () async {
      final file = await fixture();
      final before = await File(file).readAsBytes();
      final destination = p.join(temp.path, 'snapshot.db');
      await snapshot.runSnapshot(['snapshot', file, destination]);
      await snapshot.runSnapshot(['verify', destination]);
      expect(await File(file).readAsBytes(), before);
      await expectLater(
        snapshot.runSnapshot(['snapshot', file, destination]),
        throwsA(anything),
      );
      expect(
        () => requirePrivateOutput(
          p.join(Directory.current.path, 'docs', 'private.json'),
        ),
        throwsStateError,
      );
    },
  );

  test('retention preserves unknown, malformed, root, traversal and links; dry run is inert', () async {
    final service = SyncStorageService(appDataRoot: temp.path);
    await service.updateRetention(1);
    final settings = await service.load();
    Directory session(int index) {
      final id = '20260901_00000${index}_${'a' * 32}';
      final dir = Directory(p.join(settings.backupsPath, id))
        ..createSync(recursive: true);
      File(p.join(dir.path, 'metadata.json')).writeAsStringSync(
        jsonEncode({
          'owner': 'jax-sync-backup',
          'metadataVersion': 1,
          'sessionId': id,
          'createdAtUtc': '2026-09-01T00:00:00Z',
          'schemaVersion': 24,
          'protocolVersion': 11,
          'status': 'Success',
        }),
      );
      return dir;
    }

    final old = session(0);
    final newest = session(1);
    final unknown = Directory(p.join(settings.backupsPath, 'unknown'))
      ..createSync();
    final malformed = session(2);
    File(p.join(malformed.path, 'metadata.json')).writeAsStringSync('{}');
    expect(
      await isOwnedBackup(settings.backupsPath, settings.backupsPath),
      isFalse,
    );
    expect(
      await isOwnedBackup(
        settings.backupsPath,
        p.join(settings.backupsPath, '..'),
      ),
      isFalse,
    );
    expect(await service.cleanupBackups(), [old.path]);
    expect(old.existsSync(), isTrue);
    expect(await service.cleanupBackups(apply: true), [old.path]);
    expect(old.existsSync(), isFalse);
    expect(newest.existsSync(), isTrue);
    expect(unknown.existsSync(), isTrue);
    expect(malformed.existsSync(), isTrue);
    // Directory junctions may need elevated Windows privileges. A link is never followed.
    final link = Link(p.join(settings.backupsPath, 'link'));
    try {
      await link.create(newest.path);
    } on FileSystemException {
      return;
    }
    expect(await isOwnedBackup(settings.backupsPath, link.path), isFalse);
    await link.delete();
  });

  test('ADB locator honors explicit/environment/PATH/SDK with no personal fallback', () async {
    final exe = File(p.join(temp.path, Platform.isWindows ? 'adb.exe' : 'adb'))
      ..writeAsStringSync('fixture');
    WindowsDebugSyncCoordinator coordinator(
      Map<String, String> env, {
      String? explicit,
    }) => WindowsDebugSyncCoordinator(
      projectRoot: temp.path,
      storageService: SyncStorageService(appDataRoot: temp.path),
      environment: env,
      adbPath: explicit,
    );
    expect(coordinator({}, explicit: exe.path).findAdb(), exe.path);
    expect(coordinator({'JAX_ADB_PATH': exe.path}).findAdb(), exe.path);
    expect(coordinator({'PATH': temp.path}).findAdb(), exe.path);
    expect(
      coordinator({'PATH': temp.path}, explicit: 'missing').findAdb(),
      isNull,
    );
    final sdk = Directory(p.join(temp.path, 'sdk', 'platform-tools'))
      ..createSync(recursive: true);
    final sdkExe = exe.copySync(p.join(sdk.path, p.basename(exe.path)));
    for (final name in ['ANDROID_HOME', 'ANDROID_SDK_ROOT']) {
      expect(coordinator({name: p.dirname(sdk.path)}).findAdb(), sdkExe.path);
    }
    expect(coordinator({}).findAdb(), isNull);
  });
}
