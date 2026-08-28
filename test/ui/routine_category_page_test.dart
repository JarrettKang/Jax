import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/app.dart';
import 'package:jax/core/entities/routine.dart';
import 'package:jax/core/entities/routine_category.dart';
import 'package:jax/core/preferences/routine_category_collapse_store.dart';

import '../support/memory_repository.dart';

void main() {
  testWidgets(
    'Routine Category sections persist collapse by id across app rebuild',
    (tester) async {
      final now = DateTime(2026, 8, 28, 8);
      final repo = MemoryRepository()
        ..routineCategories.addAll([
          RoutineCategory(
            id: 'life',
            name: '日常起居',
            sortOrder: 0,
            createdAt: now,
            updatedAt: now,
          ),
          RoutineCategory(
            id: 'food',
            name: '饮食',
            sortOrder: 1,
            createdAt: now,
            updatedAt: now,
          ),
        ])
        ..routines.addAll([
          Routine(
            id: 'wash',
            name: '洗漱',
            routineCategoryId: 'life',
            recurrence: RoutineRecurrence.daily,
            weekdayMask: 0,
            isActive: true,
            sortOrder: 0,
            createdAt: now,
            updatedAt: now,
          ),
          Routine(
            id: 'meal',
            name: '吃饭',
            routineCategoryId: 'food',
            recurrence: RoutineRecurrence.daily,
            weekdayMask: 0,
            isActive: true,
            sortOrder: 0,
            createdAt: now,
            updatedAt: now,
          ),
        ]);
      final store = InMemoryRoutineCategoryCollapseStore();
      Widget app() => JaxApp(
        repository: repo,
        now: () => now,
        newId: () => 'new',
        routineCategoryCollapseStore: store,
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(find.text('日常'));
      await tester.pumpAndSettle();
      expect(find.text('洗漱'), findsOneWidget);
      expect(find.text('吃饭'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('routine-category-toggle-life')),
      );
      await tester.pumpAndSettle();
      expect(find.text('洗漱'), findsNothing);
      expect(find.text('吃饭'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(find.text('日常'));
      await tester.pumpAndSettle();
      expect(find.text('洗漱'), findsNothing);
      expect(find.text('吃饭'), findsOneWidget);
    },
  );
}
