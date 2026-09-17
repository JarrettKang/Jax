import '../theme/list_density.dart';

import 'package:flutter/material.dart';

import '../../core/entities/routine.dart';
import '../controllers/event_controller.dart';
import 'execution_action_buttons.dart';
import 'execution_row_shell.dart';
import '../theme/home_pilot_theme.dart';

/// Existing execution identity is retained even outside recurrence windows.
class WaitingRoutineRow extends StatelessWidget {
  const WaitingRoutineRow({
    required this.controller,
    required this.execution,
    this.operationalVisuals = false,
    super.key,
  });
  final bool operationalVisuals;
  final EventController controller;
  final RoutineExecution execution;
  @override
  Widget build(BuildContext context) {
    final routine = controller.routines
        .where((r) => r.id == execution.routineId)
        .firstOrNull;
    if (routine == null) return const SizedBox.shrink();
    final category = controller.routineCategories
        .where((c) => c.id == routine.routineCategoryId)
        .firstOrNull;
    Future<void> act(Future<String?> Function() action) async {
      final error = await action();
      if (error != null && context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error)));
      }
    }

    if (operationalVisuals) {
      return ExecutionRowShell(
        density: JaxListDensity.compact,
        title: routine.name,
        state: ExecutionVisualState.waiting,
        metadata: Text(
          '${category?.name ?? '未分类'} · ${execution.occurrenceDate}',
        ),
        actions: [
          ExecutionActionButton(
            key: ValueKey('routine-waiting-resume-${execution.id}'),
            action: ExecutionAction.continueWaiting,
            primary: false,
            style: HomePilot.buttonStyle(outlined: true),
            onPressed: () =>
                act(() => controller.resumeWaitingRoutine(execution)),
          ),
          ExecutionActionButton(
            key: ValueKey('routine-waiting-complete-${execution.id}'),
            action: ExecutionAction.complete,
            primary: false,
            style: HomePilot.buttonStyle(outlined: true),
            onPressed: () =>
                act(() => controller.completeWaitingRoutine(execution)),
          ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(routine.name, style: Theme.of(context).textTheme.titleMedium),
          Text(
            '${category?.name ?? '未分类'} · 等待中',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: ExecutionActionRow(
              children: [
                ExecutionActionButton(
                  key: ValueKey('routine-waiting-resume-${execution.id}'),
                  action: ExecutionAction.continueWaiting,
                  onPressed: () =>
                      act(() => controller.resumeWaitingRoutine(execution)),
                ),
                ExecutionActionButton(
                  key: ValueKey('routine-waiting-complete-${execution.id}'),
                  action: ExecutionAction.complete,
                  onPressed: () =>
                      act(() => controller.completeWaitingRoutine(execution)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
