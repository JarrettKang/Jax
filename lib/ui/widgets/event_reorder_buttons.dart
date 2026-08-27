import 'package:flutter/material.dart';

import '../controllers/event_controller.dart';

/// Compact, always-current sibling reorder controls for an Event.
///
/// The controller is the sole source for whether either operation is legal,
/// so every view follows the same boundary behavior.
class EventReorderButtons extends StatelessWidget {
  const EventReorderButtons({
    required this.controller,
    required this.eventId,
    required this.upKey,
    required this.downKey,
    this.onReordered,
    this.compact = false,
    super.key,
  });

  final EventController controller;
  final String eventId;
  final Key upKey;
  final Key downKey;
  final VoidCallback? onReordered;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final index = controller.siblingIndexFor(eventId);
    final count = controller.siblingCountFor(eventId);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (index > 0)
          IconButton(
            key: upKey,
            icon: const Icon(Icons.arrow_upward),
            tooltip: '上移',
            onPressed: () => _move(context, true),
            visualDensity: compact ? VisualDensity.compact : null,
            constraints: compact
                ? const BoxConstraints(minWidth: 44, minHeight: 48)
                : null,
          ),
        if (index >= 0 && index < count - 1)
          IconButton(
            key: downKey,
            icon: const Icon(Icons.arrow_downward),
            tooltip: '下移',
            onPressed: () => _move(context, false),
            visualDensity: compact ? VisualDensity.compact : null,
            constraints: compact
                ? const BoxConstraints(minWidth: 44, minHeight: 48)
                : null,
          ),
      ],
    );
  }

  Future<void> _move(BuildContext context, bool up) async {
    final error = up
        ? await controller.moveUp(eventId)
        : await controller.moveDown(eventId);
    if (error != null && context.mounted) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(error)));
    }
    if (error == null) onReordered?.call();
  }
}
