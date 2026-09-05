import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/routine.dart';
import 'package:jax/core/services/routine_service.dart';
import 'package:jax/ui/controllers/event_controller.dart';

import '../support/memory_repository.dart';

void main() {
  test('quick preference defaults off, preserves lifecycle and clears on type switch', () async {
    final repo = MemoryRepository();
    var id = 0;
    final service = RoutineService(repository: repo, newId: () => '${id++}', now: () => DateTime(2026, 9, 5, 10));
    await service.create('按需', null, RoutineRecurrence.daily, 0, type: RoutineType.onDemand);
    expect(repo.routines.single.showInHomeQuickActions, isFalse);
    Future<void> edit({bool? quick, RoutineType? type}) => service.update(repo.routines.single, '按需', null, RoutineRecurrence.daily, 0, showInHomeQuickActions: quick, type: type);
    await edit(quick: true);
    expect(repo.routines.single.isHomeQuickAction, isTrue);
    await service.setActive(repo.routines.single, false);
    expect(repo.routines.single.showInHomeQuickActions, isTrue);
    expect(repo.routines.single.isHomeQuickAction, isFalse);
    await service.setActive(repo.routines.single, true);
    expect(repo.routines.single.isHomeQuickAction, isTrue);
    await edit(type: RoutineType.scheduled);
    expect(repo.routines.single.showInHomeQuickActions, isFalse);
    await edit(type: RoutineType.onDemand);
    expect(repo.routines.single.showInHomeQuickActions, isFalse);
    expect(repo.routineExecutions, isEmpty);
    expect(repo.eventDayPlans, isEmpty);
  });

  test('quick candidates share flag and order; start resume repeat retain execution invariants', () async {
    final repo = MemoryRepository();
    var id = 0;
    var now = DateTime(2026, 9, 5, 10);
    final controller = EventController(repository: repo, newId: () => '${id++}', now: () => now);
    addTearDown(controller.dispose);
    await controller.load();
    for (final name in ['first', 'unmarked', 'last']) {
      await controller.createRoutine(name, null, RoutineRecurrence.daily, 0, type: RoutineType.onDemand, showInHomeQuickActions: name != 'unmarked');
    }
    expect(controller.homeQuickActionRoutines.map((r) => r.name), ['first', 'last']);
    expect(controller.historicalOnDemandRoutineCandidates.map((r) => r.name), ['first', 'last']);
    final first = repo.routines.first;
    expect(await controller.startRoutine(first), isNull);
    expect(repo.routineExecutions, hasLength(1));
    final executionId = repo.routineExecutions.single.id;
    expect(controller.historicalOnDemandRoutineCandidates.map((r) => r.name), ['last']);
    now = now.add(const Duration(minutes: 5));
    expect(await controller.pauseRoutine(first), isNull);
    expect(await controller.startRoutine(first), isNull);
    expect(repo.routineExecutions.single.id, executionId);
    now = now.add(const Duration(minutes: 5));
    expect(await controller.completeRoutine(first), isNull);
    expect(await controller.startRoutine(first), isNull);
    expect(repo.routineExecutions, hasLength(2));
    expect(repo.routineExecutions.where((e) => e.status != RoutineExecutionStatus.completed), hasLength(1));
    final history = List.of(repo.routineExecutions);
    await controller.updateRoutine(first, first.name, null, first.recurrence, 0, showInHomeQuickActions: false);
    expect(controller.homeQuickActionRoutines.map((r) => r.name), ['last']);
    expect(repo.routineExecutions, history);
    expect(repo.eventDayPlans, isEmpty);
  });
}
