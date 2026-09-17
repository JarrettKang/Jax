import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/routine.dart';
import 'package:jax/core/preferences/routine_category_collapse_store.dart';
import 'package:jax/ui/controllers/event_controller.dart';
import 'package:jax/ui/pages/routine_page.dart';

import '../support/memory_repository.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets(
      'three temporal pickers validate overnight and invalid order $platform',
      (tester) async {
        await tester.binding.setSurfaceSize(
          Size(platform == TargetPlatform.android ? 360 : 1200, 900),
        );
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final repo = MemoryRepository();
        var id = 0;
        final controller = EventController(
          repository: repo,
          newId: () => 'id-${id++}',
          now: () => DateTime(2026, 9, 14, 12),
        );
        await controller.load();
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: platform),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(alwaysUse24HourFormat: true),
              child: child!,
            ),
            home: Scaffold(
              body: RoutinePage(
                controller: controller,
                collapseStore: InMemoryRoutineCategoryCollapseStore(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('create-routine')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, 'Night');
        await tester.tap(
          find.byKey(const ValueKey('routine-time-recommendation-toggle')),
        );
        await tester.pumpAndSettle();
        for (final label in ['开始推荐', '理想完成前', '最晚完成前']) {
          expect(find.text(label), findsOneWidget);
        }
        Future<void> pick(String key, String hour, String minute) async {
          final button = find.byKey(ValueKey(key));
          await tester.ensureVisible(button);
          await tester.tap(button);
          await tester.pumpAndSettle();
          await tester.tap(find.byIcon(Icons.keyboard_outlined));
          await tester.pumpAndSettle();
          final inputs = find.descendant(
            of: find.byType(TimePickerDialog),
            matching: find.byType(TextField),
          );
          await tester.enterText(inputs.at(0), hour);
          await tester.enterText(inputs.at(1), minute);
          await tester.tap(find.text('OK'));
          await tester.pumpAndSettle();
        }

        await pick('routine-time-start', '11', '00');
        await pick('routine-time-end', '18', '00');
        await pick('routine-time-latest', '14', '00');
        await tester.tap(find.text('创建'));
        await tester.pumpAndSettle();
        expect(find.textContaining('推荐时间顺序'), findsOneWidget);
        expect(repo.routines, isEmpty);
        await pick('routine-time-start', '22', '30');
        await pick('routine-time-end', '00', '30');
        await pick('routine-time-latest', '02', '00');
        await tester.tap(find.text('创建'));
        await tester.pumpAndSettle();
        final config = repo.routines.single.timeRecommendation!;
        expect(config.startMinute, 1350);
        expect(config.endMinute, 30);
        expect(config.latestEndMinute, 120);
        expect(repo.routines.single.type, RoutineType.scheduled);
        expect(tester.takeException(), isNull);
        controller.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
