import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:jax/core/preferences/app_preferences.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/database/platform_database.dart';
import 'package:jax/data/preferences/file_app_preferences_store.dart';
import 'package:jax/main.dart' as app;
import 'package:jax/ui/pages/home_page.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as android;

// Run only in a newly created emulator or a private RC APPDATA directory.
// Refuses an existing database; never clears or replaces user data.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'RC fresh production entry creates schema and navigates all pages',
    (tester) async {
      expect(
        const bool.fromEnvironment('JAX_RC_ISOLATED'),
        isTrue,
        reason: 'Explicit isolated RC environment required.',
      );
      final String filename;
      if (Platform.isWindows) {
        final root = Platform.environment['APPDATA']!;
        expect(p.split(root), containsAllInOrder(['.local_private', 'rc']));
        filename = p.join(root, 'Jax', 'jax.db');
      } else {
        expect(Platform.isAndroid, isTrue);
        filename = p.join(await android.getDatabasesPath(), 'jax.db');
      }
      expect(
        File(filename).existsSync(),
        isFalse,
        reason: 'Fresh database required; no reset is allowed.',
      );
      final preferences = FileAppPreferencesStore(
        File(p.join(p.dirname(filename), 'app_preferences.json')),
      );
      expect((await preferences.load()).assistantName, defaultAssistantName);
      await app.main([]);
      await tester.pumpAndSettle();
      final home = tester.widget<HomePage>(find.byType(HomePage));
      Future<void> settleDatabaseLoads() async {
        for (var attempt = 0; attempt < 200; attempt++) {
          await tester.pump(const Duration(milliseconds: 50));
          if (!home.controller.loading &&
              home.planningController?.loading != true) {
            await tester.pumpAndSettle();
            return;
          }
        }
        fail('Database-backed controllers did not finish loading.');
      }

      await settleDatabaseLoads();
      expect(tester.takeException(), isNull);
      expect(File(filename).existsSync(), isTrue);
      final database = await openPlatformDatabase();
      expect(
        (await database.database.rawQuery('PRAGMA user_version'))
            .single
            .values
            .single,
        AppDatabase.schemaVersion,
      );
      expect(
        (await database.database.rawQuery('PRAGMA integrity_check'))
            .single
            .values
            .single,
        'ok',
      );
      expect(
        await database.database.rawQuery('PRAGMA foreign_key_check'),
        isEmpty,
      );
      for (final page in ['世界', '规划', '今日', '日常', '记录', '首页']) {
        await tester.tap(find.text(page).last);
        await settleDatabaseLoads();
        expect(tester.takeException(), isNull, reason: page);
      }
      await tester.tap(find.byKey(const ValueKey('open-settings')));
      await tester.pumpAndSettle();
      expect(find.text(defaultAssistantName), findsWidgets);
      expect(tester.takeException(), isNull);
      await settleDatabaseLoads();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await database.close();
    },
  );
}
