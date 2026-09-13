import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';
import 'package:jax/data/repositories/sqlite_planning_repository.dart';
import 'package:jax/data/repositories/sqlite_world_node_repository.dart';
import 'package:jax/ui/controllers/planning_controller.dart';
import 'package:jax/ui/pages/planning_page.dart';

import '../support/world_map_fixture.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets(
      'draft inline edit preserves facts and isolates controls $platform',
      (tester) async {
        await tester.runAsync(() async {
          Future<void> settle() async {
            await Future<void>.delayed(const Duration(milliseconds: 150));
            await tester.pumpAndSettle();
          }

          await tester.binding.setSurfaceSize(
            Size(platform == TargetPlatform.android ? 390 : 1200, 850),
          );
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final app = await AppDatabase.inMemory();
          addTearDown(app.close);
          await seedWorldMapFixture(app);
          final repo = SqlitePlanningRepository(app);
          await repo.createPlanItem(
            id: 'edit-draft',
            planId: 'fixture-plan',
            title: 'Original',
            note: 'Keep note',
            now: DateTime.now(),
          );
          final c = PlanningController(
            planningRepository: repo,
            worldNodeRepository: SqliteWorldNodeRepository(app),
            eventRepository: SqliteEventRepository(app),
            newId: () => 'unused',
            now: DateTime.now,
          );
          addTearDown(c.dispose);
          await c.load();
          final before = (await app.database.query(
            'plan_items',
            where: 'id = ?',
            whereArgs: ['edit-draft'],
          )).single;
          final facts = {
            for (final table in [
              'plans',
              'events',
              'event_day_plans',
              'run_segments',
              'sync_tombstones',
            ])
              table: await app.database.query(table),
          };
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(platform: platform),
              home: PlanDetailPage(controller: c, planId: 'fixture-plan'),
            ),
          );
          await settle();
          final entry = find.byKey(const ValueKey('draft-edit-edit-draft'));
          final input = find.byKey(const ValueKey('draft-title-edit-draft'));
          Future<void> begin() async {
            await tester.ensureVisible(entry);
            await tester.tap(entry);
            await settle();
          }

          await begin();
          expect(find.byType(AlertDialog), findsNothing);
          final field = tester.widget<TextField>(input);
          expect(field.focusNode!.hasFocus, isTrue);
          expect(field.controller!.selection.baseOffset, 'Original'.length);
          await tester.enterText(input, 'Renamed');
          await c.load();
          await settle();
          await c.moveItem(
            c.itemsFor('fixture-plan').firstWhere((i) => i.id == 'edit-draft'),
            0,
          );
          await settle();
          expect(tester.widget<TextField>(input).focusNode!.hasFocus, isTrue);
          await c.moveItem(
            c.itemsFor('fixture-plan').firstWhere((i) => i.id == 'edit-draft'),
            2,
          );
          await settle();
          tester.view.viewInsets = const FakeViewPadding(bottom: 300);
          addTearDown(tester.view.resetViewInsets);
          await settle();
          expect(
            tester.getBottomRight(input).dy,
            lessThanOrEqualTo(
              tester
                  .getBottomRight(find.byKey(const ValueKey('plan-detail')))
                  .dy,
            ),
          );
          tester.view.resetViewInsets();
          await settle();
          expect(tester.widget<TextField>(input).controller!.text, 'Renamed');
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await settle();
          expect(input, findsNothing);
          final after = (await app.database.query(
            'plan_items',
            where: 'id = ?',
            whereArgs: ['edit-draft'],
          )).single;
          for (final key in before.keys.where(
            (k) => k != 'title' && k != 'updated_at_utc',
          )) {
            expect(after[key], before[key], reason: key);
          }
          expect(after['title'], 'Renamed');
          await begin();
          await tester.enterText(input, '   ');
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await settle();
          expect(find.text('Renamed'), findsOneWidget);
          await begin();
          await tester.enterText(input, 'Outside save');
          await tester.tap(find.text('计划步骤'));
          await settle();
          expect(input, findsNothing);
          expect(find.text('Outside save'), findsOneWidget);
          await begin();
          await tester.enterText(input, 'Discard this');
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await settle();
          expect(find.text('Outside save'), findsOneWidget);
          final row = find.byKey(const ValueKey('plan-item-edit-draft'));
          await tester.tap(
            find.descendant(
              of: row,
              matching: find.byType(PopupMenuButton<String>),
            ),
          );
          await settle();
          expect(find.text('编辑详情'), findsOneWidget);
          expect(input, findsNothing);
          await tester.tapAt(const Offset(10, 100));
          await settle();
          await tester.tap(
            find.byKey(const ValueKey('toggle-next-edit-draft')),
          );
          await settle();
          expect(input, findsNothing);
          for (final status in ['next', 'dispatched', 'done', 'dropped']) {
            // UI-only fixture states; no dispatch or real execution is performed.
            await app.database.update(
              'plan_items',
              {'status': status},
              where: 'id = ?',
              whereArgs: ['edit-draft'],
            );
            await c.load();
            await settle();
            await tester.tap(find.text('Outside save'));
            await settle();
            expect(input, findsNothing, reason: status);
          }
          for (final table in facts.keys) {
            expect(
              await app.database.query(table),
              facts[table],
              reason: table,
            );
          }
          expect(await app.database.query('plan_items'), hasLength(3));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        });
      },
    );
  }
}
