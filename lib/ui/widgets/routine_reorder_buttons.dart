import 'package:flutter/material.dart';

import '../controllers/event_controller.dart';

/// Reorders Routine definitions by identity. The controller serializes moves
/// and derives each target from the latest persisted order.
class RoutineReorderButtons extends StatelessWidget {
  const RoutineReorderButtons({
    required this.controller,
    required this.routineId,
    required this.index,
    required this.count,
    super.key,
  });

  final EventController controller;
  final String routineId;
  final int index;
  final int count;

  @override
  Widget build(BuildContext context) => SizedBox(
    key: ValueKey('routine-reorder-slot-$routineId'),
    width: 96,
    child: Row(
      children: [
        SizedBox(
          width: 48,
          child: index > 0
              ? IconButton(
                  key: ValueKey('routine-up-$routineId'),
                  tooltip: '上移',
                  onPressed: () => _move(context, true),
                  icon: const Icon(Icons.arrow_upward),
                )
              : null,
        ),
        SizedBox(
          width: 48,
          child: index < count - 1
              ? IconButton(
                  key: ValueKey('routine-down-$routineId'),
                  tooltip: '下移',
                  onPressed: () => _move(context, false),
                  icon: const Icon(Icons.arrow_downward),
                )
              : null,
        ),
      ],
    ),
  );

  Future<void> _move(BuildContext context, bool up) async {
    final error = up
        ? await controller.moveRoutineUp(routineId)
        : await controller.moveRoutineDown(routineId);
    if (error != null && context.mounted) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(error)));
    }
  }
}
