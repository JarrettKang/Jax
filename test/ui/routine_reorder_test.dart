import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/app.dart';
import 'package:jax/core/entities/routine.dart';

import '../support/memory_repository.dart';

void main() {
  final now = DateTime.utc(2026, 8, 28, 12);

  Routine routine(String id, int order, {bool active = true}) => Routine(
    id: id,
    name: id,
    recurrence: RoutineRecurrence.daily,
    weekdayMask: 0,
    isActive: active,
    sortOrder: order,
    createdAt: now,
    updatedAt: now,
  );

  Future<void> openRoutinePage(WidgetTester tester) async {
    await tester.tap(find.text('日常'));
    await tester.pumpAndSettle();
  }

  testWidgets('rapid routine moves use each latest persisted order', (
    tester,
  ) async {
    final repository = MemoryRepository()
      ..routines.addAll([
        routine('A', 0),
        routine('B', 1),
        routine('C', 2),
        routine('D', 3),
        routine('E', 4),
      ]);
    await tester.pumpWidget(JaxApp(repository: repository, now: () => now));
    await tester.pumpAndSettle();
    await openRoutinePage(tester);

    await tester.tap(find.byKey(const ValueKey('routine-up-C')));
    await tester.tap(find.byKey(const ValueKey('routine-up-C')));
    await tester.pumpAndSettle();

    expect((await repository.getRoutines()).map((routine) => routine.id), [
      'C',
      'A',
      'B',
      'D',
      'E',
    ]);
  });

  testWidgets('Routine moves stay deterministic across alternating actions', (
    tester,
  ) async {
    final repository = MemoryRepository()
      ..routines.addAll([
        routine('A', 0),
        routine('B', 1),
        routine('C', 2),
        routine('D', 3),
        routine('E', 4),
      ]);
    await tester.pumpWidget(JaxApp(repository: repository, now: () => now));
    await tester.pumpAndSettle();
    await openRoutinePage(tester);

    await tester.tap(find.byKey(const ValueKey('routine-up-C')));
    await tester.tap(find.byKey(const ValueKey('routine-up-D')));
    await tester.tap(find.byKey(const ValueKey('routine-down-C')));
    await tester.pumpAndSettle();

    expect((await repository.getRoutines()).map((routine) => routine.id), [
      'A',
      'D',
      'C',
      'B',
      'E',
    ]);
    expect(find.byKey(const ValueKey('routine-up-A')), findsNothing);
    expect(find.byKey(const ValueKey('routine-down-E')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('routine-down-A')));
    await tester.pumpAndSettle();
    expect((await repository.getRoutines()).map((routine) => routine.id), [
      'D',
      'A',
      'C',
      'B',
      'E',
    ]);
  });

  testWidgets('Routine reorder boundaries follow the active management group', (
    tester,
  ) async {
    final repository = MemoryRepository()
      ..routines.addAll([
        routine('A', 0),
        routine('inactive', 1, active: false),
        routine('B', 2),
      ]);
    await tester.pumpWidget(JaxApp(repository: repository, now: () => now));
    await tester.pumpAndSettle();
    await openRoutinePage(tester);

    expect(find.byKey(const ValueKey('routine-up-A')), findsNothing);
    expect(find.byKey(const ValueKey('routine-down-B')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('routine-up-B')));
    await tester.pumpAndSettle();
    expect((await repository.getRoutines()).map((routine) => routine.id), [
      'B',
      'A',
      'inactive',
    ]);
    expect(find.byKey(const ValueKey('routine-up-B')), findsNothing);
    expect(find.byKey(const ValueKey('routine-down-A')), findsNothing);
  });
}
