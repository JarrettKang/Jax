import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/app.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/preferences/sqlite_world_category_collapse_store.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';
import 'package:jax/data/repositories/sqlite_world_node_repository.dart';
import 'package:jax/data/repositories/sqlite_planning_repository.dart';
import 'package:jax/data/sync/sqlite_sync_snapshot_adapter.dart';
import 'package:jax/ui/controllers/planning_controller.dart';
import 'package:jax/ui/pages/world_page.dart';
import 'package:jax/ui/widgets/world_node_tree_guide.dart';

import '../support/world_map_fixture.dart';
import '../support/world_tree_interactions.dart';

void main() {
  for (final width in [390.0, 1400.0]) {
    testWidgets(
      'realistic World outline, six levels and zero business writes at $width',
      (tester) async {
        await tester.runAsync(() async {
          final directory = Platform.environment['JAX_WORLD_CAPTURE_DIR'];
          final fontPath = Platform.environment['JAX_WORLD_FONT'];
          final iconsPath = Platform.environment['JAX_WORLD_ICONS'];
          if (directory != null && fontPath != null && iconsPath != null) {
            for (final (family, path) in [
              ('WorldCapture', fontPath),
              ('MaterialIcons', iconsPath),
            ]) {
              final loader = FontLoader(family)
                ..addFont(
                  File(path)
                      .readAsBytes()
                      .then((bytes) => ByteData.sublistView(bytes)),
                );
              await loader.load();
            }
          }
          await tester.binding.setSurfaceSize(Size(width, 844));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final app = await AppDatabase.inMemory();
          addTearDown(app.close);
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
          final capture = GlobalKey();
          final theme = buildJaxTheme(
            width < 600 ? TargetPlatform.android : TargetPlatform.windows,
          );
          await tester.pumpWidget(
            MaterialApp(
              theme: directory != null && fontPath != null
                  ? theme.copyWith(
                      textTheme: theme.textTheme.apply(
                        fontFamily: 'WorldCapture',
                      ),
                    )
                  : theme,
              home: RepaintBoundary(
                key: capture,
                child: WorldPage(
                  controller: controller,
                  worldCategoryCollapseStore: SqliteWorldCategoryCollapseStore(
                    app,
                  ),
                ),
              ),
            ),
          );
          while (controller.loading) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          await tester.pumpAndSettle();
          expect(controller.error, isNull);
          expect(find.text('2 个下一步'), findsOneWidget);
          expect(find.text('尚无计划'), findsNothing);
          final guide = tester.widget<WorldNodeTreeGuideFrame>(
            find.byKey(ValueKey('world-node-guide-${mapNodeId(4)}')),
          );
          expect(guide.visualContext.depth, 2);
          expect(guide.visualContext.isLastSibling, isTrue);
          expect(guide.visualContext.ancestorHasNextSibling, [false]);
          expect(find.byType(Card), findsNothing);
          if (directory != null) {
            final image =
                await (capture.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await Directory(directory).create(recursive: true);
            await File('$directory/world-${width.toInt()}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          }
          final deep = find.byKey(ValueKey('world-node-${mapNodeId(14)}'));
          await tester.ensureVisible(deep);
          await tester.pumpAndSettle();
          final deepGuide = tester.widget<WorldNodeTreeGuideFrame>(
            find.byKey(ValueKey('world-node-guide-${mapNodeId(14)}')),
          );
          expect(deepGuide.visualContext.depth, 5);
          expect(tester.getSize(deep).width, greaterThan(100));
          await tester.tap(
            find.byKey(ValueKey('world-node-more-${mapNodeId(14)}')),
          );
          await tester.pumpAndSettle();
          expect(find.text('移动到…'), findsOneWidget);
          await tester.tapAt(const Offset(2, 2));
          await tester.pumpAndSettle();
          final branch = find.byKey(
            ValueKey('world-node-branch-${mapNodeId(8)}'),
          );
          await tester.ensureVisible(branch);
          await tester.tap(branch);
          await tester.pumpAndSettle();
          expect(find.text('C1'), findsNothing);
          expect(find.text('C2'), findsNothing);
          await exerciseWorldTreeBrowsing(
            tester,
            SqliteWorldCategoryCollapseStore(app),
            keyboard: width > 600,
          );
          final after = await SqliteSyncSnapshotAdapter(app.database).read();
          expect(after.businessFingerprint, before.businessFingerprint);
          expect(tester.takeException(), isNull);
        });
      },
    );
  }
}
