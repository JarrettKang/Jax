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
import 'package:jax/data/sync/sqlite_sync_snapshot_adapter.dart';
import 'package:jax/ui/controllers/planning_controller.dart';
import 'package:jax/ui/pages/world_page.dart';
import 'package:sqflite/sqflite.dart';

import '../test/support/world_map_fixture.dart';
import '../test/support/world_tree_interactions.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native compact World fixture is read only', (tester) async {
    final directory = await Directory.systemTemp.createTemp('jax-world-map-');
    final file = '${directory.path}/fixture.db';
    final app = Platform.isAndroid
        ? await AppDatabase.openWithFactory(file, databaseFactory)
        : await AppDatabase.open(file);
    addTearDown(() async {
      await app.close();
      await directory.delete(recursive: true);
    });
    await seedWorldMapFixture(app);
    final controller = PlanningController(
      planningRepository: SqlitePlanningRepository(app),
      worldNodeRepository: SqliteWorldNodeRepository(app),
      eventRepository: SqliteEventRepository(app),
      newId: () => 'unused',
      now: () => DateTime(2026, 9, 8, 12),
    );
    addTearDown(controller.dispose);
    final before = await SqliteSyncSnapshotAdapter(app.database).read();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildJaxTheme(
          Platform.isAndroid ? TargetPlatform.android : TargetPlatform.windows,
        ),
        home: WorldPage(
          controller: controller,
          worldCategoryCollapseStore: SqliteWorldCategoryCollapseStore(app),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('看分层倾斜角'), findsOneWidget);
    expect(find.text('2 个下一步'), findsNothing);
    expect(
      controller
          .itemsFor('fixture-plan')
          .where((item) => item.status.name == 'next'),
      hasLength(2),
    );
    expect(find.text('尚无计划'), findsNothing);
    await exerciseWorldTreeBrowsing(
      tester,
      SqliteWorldCategoryCollapseStore(app),
    );
    const hold = int.fromEnvironment('WORLD_VISUAL_HOLD_SECONDS');
    if (hold > 0) {
      binding.shouldPropagateDevicePointerEvents = true;
      final watch = Stopwatch()..start();
      while (watch.elapsed < const Duration(seconds: hold)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      }
      binding.shouldPropagateDevicePointerEvents = false;
    }
    final deep = find.byKey(ValueKey('world-node-${mapNodeId(14)}'));
    await tester.ensureVisible(deep);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('world-node-more-${mapNodeId(14)}')));
    await tester.pumpAndSettle();
    expect(find.text('移动到…'), findsOneWidget);
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    final after = await SqliteSyncSnapshotAdapter(app.database).read();
    expect(after.businessFingerprint, before.businessFingerprint);
    expect(tester.takeException(), isNull);
  });
}
