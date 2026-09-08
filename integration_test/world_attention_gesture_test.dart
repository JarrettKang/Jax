import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:jax/app.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/preferences/sqlite_world_category_collapse_store.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';
import 'package:jax/data/repositories/sqlite_planning_repository.dart';
import 'package:jax/data/repositories/sqlite_world_node_repository.dart';
import 'package:jax/ui/controllers/planning_controller.dart';
import 'package:jax/ui/pages/world_page.dart';
import 'package:sqflite/sqflite.dart';

import '../test/support/world_attention_interactions.dart';
import '../test/support/world_map_fixture.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native World attention gestures use an isolated fixture', (
    tester,
  ) async {
    final directory = await Directory.systemTemp.createTemp(
      'jax-world-attention-',
    );
    final file = '${directory.path}/fixture.db';
    final app = Platform.isAndroid
        ? await AppDatabase.openWithFactory(file, databaseFactory)
        : await AppDatabase.open(file);
    addTearDown(() async {
      await app.close();
      await directory.delete(recursive: true);
    });
    await seedWorldAttentionFixture(app);
    final controller = PlanningController(
      planningRepository: SqlitePlanningRepository(app),
      worldNodeRepository: SqliteWorldNodeRepository(app),
      eventRepository: SqliteEventRepository(app),
      newId: () => 'unused',
      now: () => DateTime(2026, 9, 8, 13),
    );
    addTearDown(controller.dispose);
    final store = SqliteWorldCategoryCollapseStore(app);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildJaxTheme(
          Platform.isAndroid ? TargetPlatform.android : TargetPlatform.windows,
        ),
        home: SafeArea(
          child: WorldPage(
            controller: controller,
            worldCategoryCollapseStore: store,
          ),
        ),
      ),
    );
    await settleWorldAttention(tester);
    await exerciseWorldAttention(
      tester,
      app,
      controller,
      store,
      desktop: Platform.isWindows,
    );

    const hold = int.fromEnvironment('WORLD_ATTENTION_HOLD_SECONDS');
    if (hold > 0) {
      await tester.ensureVisible(
        find.byKey(ValueKey('world-node-main-${mapNodeId(1)}')),
      );
      await tester.pumpAndSettle();
      debugPrint(
        'WORLD_ATTENTION_MANUAL_READY: isolated fixture, schema ${AppDatabase.schemaVersion}',
      );
      var lastFocus = '';
      void logAttention() {
        final focus = controller.worldNodes
            .where((node) => node.isFocused)
            .map((node) => node.name)
            .join(', ');
        if (focus != lastFocus) {
          lastFocus = focus;
          debugPrint('WORLD_ATTENTION_FOCUS: $focus');
        }
      }

      controller.addListener(logAttention);
      binding.shouldPropagateDevicePointerEvents = true;
      try {
        final watch = Stopwatch()..start();
        while (watch.elapsed < const Duration(seconds: hold)) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump();
        }
      } finally {
        binding.shouldPropagateDevicePointerEvents = false;
        controller.removeListener(logAttention);
      }
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
