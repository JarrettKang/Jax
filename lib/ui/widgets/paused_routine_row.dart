import '../theme/list_density.dart';

import 'package:flutter/material.dart';

import '../../core/entities/routine.dart';
import '../../core/entities/execution_capabilities.dart';
import '../controllers/event_controller.dart';
import 'execution_action_buttons.dart';
import 'execution_row_shell.dart';
import '../theme/home_pilot_theme.dart';

class PausedRoutineRow extends StatelessWidget {
  const PausedRoutineRow({
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
    Future<void> act(Future<String?> action) async {
      final error = await action;
      if (error != null && context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error)));
      }
    }

    if (operationalVisuals) {
      return ExecutionRowShell(
        density: JaxListDensity.compact,
        title: routine.name,
        state: ExecutionVisualState.paused,
        metadata: Text(execution.occurrenceDate),
        actions: [
          if (execution.status.canResume)
            ExecutionActionButton(
              key: ValueKey('routine-paused-resume-${execution.id}'),
              action: ExecutionAction.resume,
              label: '继续',
              primary: false,
              style: HomePilot.buttonStyle(outlined: true),
              onPressed: () =>
                  act(controller.resumeRoutineExecution(execution)),
            ),
          if (execution.status.canComplete)
            ExecutionActionButton(
              key: ValueKey('routine-paused-complete-${execution.id}'),
              action: ExecutionAction.complete,
              primary: false,
              style: HomePilot.buttonStyle(outlined: true),
              onPressed: () =>
                  act(controller.completeRoutineExecution(execution)),
            ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(routine.name, style: Theme.of(context).textTheme.titleMedium),
          Text(
            '已暂停 · ${execution.occurrenceDate}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: ExecutionActionRow(
              children: [
                if (execution.status.canResume)
                  ExecutionActionButton(
                    key: ValueKey('routine-paused-resume-${execution.id}'),
                    action: ExecutionAction.resume,
                    onPressed: () =>
                        act(controller.resumeRoutineExecution(execution)),
                  ),
                if (execution.status.canComplete)
                  ExecutionActionButton(
                    key: ValueKey('routine-paused-complete-${execution.id}'),
                    action: ExecutionAction.complete,
                    onPressed: () =>
                        act(controller.completeRoutineExecution(execution)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
