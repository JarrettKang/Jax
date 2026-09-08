import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/app.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/preferences/sqlite_world_category_collapse_store.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';
import 'package:jax/data/repositories/sqlite_planning_repository.dart';
import 'package:jax/data/repositories/sqlite_world_node_repository.dart';
import 'package:jax/ui/controllers/planning_controller.dart';
import 'package:jax/ui/pages/world_page.dart';

import '../support/world_attention_interactions.dart';
import '../support/world_map_fixture.dart';

void main() {
  for (final desktop in [false, true]) {
    testWidgets(
      'World pointer attention is isolated and preserves execution facts: desktop=$desktop',
      (tester) async {
        await tester.runAsync(() async {
          await tester.binding.setSurfaceSize(Size(desktop ? 1400 : 390, 844));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final app = await AppDatabase.inMemory();
          addTearDown(app.close);
          await seedWorldAttentionFixture(app);
          final controller = PlanningController(
            planningRepository: SqlitePlanningRepository(app),
            worldNodeRepository: SqliteWorldNodeRepository(app),
            eventRepository: SqliteEventRepository(app),
            newId: () => 'unused',
            now: () => DateTime(2026, 9, 8, 13),
          );
          addTearDown(controller.dispose);
          await controller.load();
          final store = SqliteWorldCategoryCollapseStore(app);
          await tester.pumpWidget(
            MaterialApp(
              theme: buildJaxTheme(
                desktop ? TargetPlatform.windows : TargetPlatform.android,
              ),
              home: WorldPage(
                controller: controller,
                worldCategoryCollapseStore: store,
              ),
            ),
          );
          await settleWorldAttention(tester);
          await exerciseWorldAttention(
            tester,
            app,
            controller,
            store,
            desktop: desktop,
          );
          await tester.pumpWidget(const SizedBox());
        });
      },
    );
  }

  testWidgets('failed attention write keeps focus visual and reports error', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final app = await AppDatabase.inMemory();
      addTearDown(app.close);
      await seedWorldMapFixture(app);
      final controller = PlanningController(
        planningRepository: SqlitePlanningRepository(app),
        worldNodeRepository: _FailingFocusRepository(app),
        eventRepository: SqliteEventRepository(app),
        newId: () => 'unused',
        now: DateTime.now,
      );
      addTearDown(controller.dispose);
      await controller.load();
      final store = SqliteWorldCategoryCollapseStore(app);
      await tester.pumpWidget(
        MaterialApp(
          home: WorldPage(
            controller: controller,
            worldCategoryCollapseStore: store,
          ),
        ),
      );
      await settleWorldAttention(tester);
      await doubleTapWorld(
        tester,
        find.byKey(ValueKey('world-node-main-${mapNodeId(0)}')),
      );
      expect(controller.nodeFor(mapNodeId(0))!.isFocused, isFalse);
      expect(find.textContaining('attention write failed'), findsOneWidget);
      expect(await store.loadCollapsedSectionKeys(), isEmpty);
      await tester.pumpWidget(const SizedBox());
    });
  });
}

class _FailingFocusRepository extends SqliteWorldNodeRepository {
  _FailingFocusRepository(super.database);
  @override
  Future<void> setWorldNodeFocus(
    String id,
    bool isFocused,
    DateTime updatedAt,
  ) async {
    throw StateError('attention write failed');
  }
}
