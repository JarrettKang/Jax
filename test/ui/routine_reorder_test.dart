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

    tester
        .widget<PopupMenuButton<String>>(
          find.byKey(const ValueKey('routine-more-C')),
        )
        .onSelected!('up');
    tester
        .widget<PopupMenuButton<String>>(
          find.byKey(const ValueKey('routine-more-C')),
        )
        .onSelected!('up');
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

    tester
        .widget<PopupMenuButton<String>>(
          find.byKey(const ValueKey('routine-more-C')),
        )
        .onSelected!('up');
    tester
        .widget<PopupMenuButton<String>>(
          find.byKey(const ValueKey('routine-more-D')),
        )
        .onSelected!('up');
    tester
        .widget<PopupMenuButton<String>>(
          find.byKey(const ValueKey('routine-more-C')),
        )
        .onSelected!('down');
    await tester.pumpAndSettle();

    expect((await repository.getRoutines()).map((routine) => routine.id), [
      'A',
      'D',
      'C',
      'B',
      'E',
    ]);
    await tester.tap(find.byKey(const ValueKey('routine-more-A')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('routine-up-A')), findsNothing);
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('routine-more-E')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('routine-more-E')));
    await tester.pumpAndSettle();
    expect(find.text('编辑'), findsOneWidget);
    expect(find.byKey(const ValueKey('routine-down-E')), findsNothing);
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    tester
        .widget<PopupMenuButton<String>>(
          find.byKey(const ValueKey('routine-more-A')),
        )
        .onSelected!('down');
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

    await tester.tap(find.byKey(const ValueKey('routine-more-A')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('routine-up-A')), findsNothing);
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('routine-more-B')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('routine-down-B')), findsNothing);
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    tester
        .widget<PopupMenuButton<String>>(
          find.byKey(const ValueKey('routine-more-B')),
        )
        .onSelected!('up');
    await tester.pumpAndSettle();
    expect((await repository.getRoutines()).map((routine) => routine.id), [
      'B',
      'A',
      'inactive',
    ]);
    await tester.tap(find.byKey(const ValueKey('routine-more-B')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('routine-up-B')), findsNothing);
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('routine-more-A')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('routine-down-A')), findsNothing);
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
  });
}
