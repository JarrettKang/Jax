import 'package:flutter/material.dart';

import '../controllers/event_controller.dart';

class EventReorderHandle extends StatelessWidget {
  const EventReorderHandle({
    required this.controller,
    required this.eventId,
    super.key,
  });

  final EventController controller;
  final String eventId;

  @override
  Widget build(BuildContext context) {
    if (controller.siblingCountFor(eventId) < 2) return const SizedBox.shrink();
    return Tooltip(
      message: '拖动调整顺序',
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: Draggable<String>(
          data: eventId,
          feedback: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(8),
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Icon(Icons.drag_handle),
            ),
          ),
          childWhenDragging: const SizedBox(width: 48, height: 48),
          child: const SizedBox(
            width: 48,
            height: 48,
            child: Center(child: Icon(Icons.drag_handle)),
          ),
        ),
      ),
    );
  }
}

class EventReorderDropTarget extends StatelessWidget {
  const EventReorderDropTarget({
    required this.controller,
    required this.eventId,
    required this.child,
    super.key,
  });

  final EventController controller;
  final String eventId;
  final Widget child;

  @override
  Widget build(BuildContext context) => DragTarget<String>(
    onWillAcceptWithDetails: (details) =>
        details.data != eventId &&
        controller.sameReorderGroup(details.data, eventId),
    onAcceptWithDetails: (details) => _drop(context, details),
    builder: (context, candidates, _) => DecoratedBox(
      decoration: BoxDecoration(
        border: candidates.isEmpty
            ? null
            : Border(
                top: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 3,
                ),
              ),
      ),
      child: child,
    ),
  );

  Future<void> _drop(
    BuildContext context,
    DragTargetDetails<String> details,
  ) async {
    final targetBox = context.findRenderObject()! as RenderBox;
    final localY = targetBox.globalToLocal(details.offset).dy;
    var targetIndex = controller.siblingIndexFor(eventId);
    if (localY > targetBox.size.height / 2) targetIndex++;
    final sourceIndex = controller.siblingIndexFor(details.data);
    if (sourceIndex < targetIndex) targetIndex--;
    final error = await controller.reorder(details.data, targetIndex);
    if (error != null && context.mounted) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(error)));
    }
  }
}
