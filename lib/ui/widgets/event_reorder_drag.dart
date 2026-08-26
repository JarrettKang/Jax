import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../controllers/event_controller.dart';

/// The handle is deliberately the only drag origin. The preview, however,
/// represents the whole event visual unit rather than the small handle.
class EventReorderHandle extends StatelessWidget {
  const EventReorderHandle({
    required this.controller,
    required this.eventId,
    required this.title,
    required this.subtitle,
    this.rowStyle = false,
    super.key,
  });

  final EventController controller;
  final String eventId;
  final String title;
  final String subtitle;
  final bool rowStyle;

  @override
  Widget build(BuildContext context) {
    if (controller.siblingCountFor(eventId) < 2) return const SizedBox.shrink();
    final maxWidth = math.min(MediaQuery.sizeOf(context).width - 24, 620.0);
    return Tooltip(
      message: '拖动调整顺序',
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: Draggable<String>(
          key: ValueKey('reorder-handle-$eventId'),
          data: eventId,
          feedback: Material(
            color: Colors.transparent,
            child: ConstrainedBox(
              constraints: BoxConstraints.tightFor(width: maxWidth),
              child: Opacity(
                opacity: .92,
                child: EventReorderFeedback(
                  title: title,
                  subtitle: subtitle,
                  rowStyle: rowStyle,
                ),
              ),
            ),
          ),
          childWhenDragging: const SizedBox(
            width: 48,
            height: 48,
            child: Center(child: Icon(Icons.drag_handle, color: Colors.grey)),
          ),
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

class EventReorderFeedback extends StatelessWidget {
  const EventReorderFeedback({
    required this.title,
    required this.subtitle,
    required this.rowStyle,
    super.key,
  });

  final String title;
  final String subtitle;
  final bool rowStyle;

  @override
  Widget build(BuildContext context) {
    final content = ListTile(
      leading: rowStyle ? const Icon(Icons.drag_indicator) : null,
      title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.drag_handle),
    );
    if (rowStyle) {
      return Material(
        elevation: 10,
        borderRadius: BorderRadius.circular(8),
        child: content,
      );
    }
    return Card(elevation: 10, child: content);
  }
}

/// A full-width drop zone. Its child includes the visual card margin or row
/// height, so consecutive list entries retain continuous hit coverage without
/// altering the responsive page layout.
class EventReorderDropTarget extends StatefulWidget {
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
  State<EventReorderDropTarget> createState() => _EventReorderDropTargetState();
}

class _EventReorderDropTargetState extends State<EventReorderDropTarget> {
  bool? _insertAfter;

  bool _accepts(String sourceId) =>
      sourceId != widget.eventId &&
      widget.controller.sameReorderGroup(sourceId, widget.eventId);

  void _updateIndicator(DragTargetDetails<String> details) {
    if (!_accepts(details.data)) return;
    final box = context.findRenderObject()! as RenderBox;
    final insertAfter =
        box.globalToLocal(details.offset).dy > box.size.height / 2;
    if (_insertAfter != insertAfter) setState(() => _insertAfter = insertAfter);
  }

  @override
  Widget build(BuildContext context) => DragTarget<String>(
    key: ValueKey('reorder-target-${widget.eventId}'),
    hitTestBehavior: HitTestBehavior.translucent,
    onWillAcceptWithDetails: (details) => _accepts(details.data),
    onMove: _updateIndicator,
    onLeave: (_) {
      if (_insertAfter != null) setState(() => _insertAfter = null);
    },
    onAcceptWithDetails: _drop,
    builder: (context, candidates, _) {
      final active = candidates.isNotEmpty;
      final color = Theme.of(context).colorScheme.primary;
      return DecoratedBox(
        decoration: !active
            ? const BoxDecoration()
            : BoxDecoration(
                border: Border(
                  top: _insertAfter == true
                      ? BorderSide.none
                      : BorderSide(color: color, width: 3),
                  bottom: _insertAfter == true
                      ? BorderSide(color: color, width: 3)
                      : BorderSide.none,
                ),
              ),
        child: widget.child,
      );
    },
  );

  Future<void> _drop(DragTargetDetails<String> details) async {
    final box = context.findRenderObject()! as RenderBox;
    final insertAfter =
        box.globalToLocal(details.offset).dy > box.size.height / 2;
    var targetIndex = widget.controller.siblingIndexFor(widget.eventId);
    if (insertAfter) targetIndex++;
    final sourceIndex = widget.controller.siblingIndexFor(details.data);
    if (sourceIndex < targetIndex) targetIndex--;
    if (sourceIndex == targetIndex) {
      if (mounted) setState(() => _insertAfter = null);
      return;
    }
    final error = await widget.controller.reorder(details.data, targetIndex);
    if (!mounted) return;
    setState(() => _insertAfter = null);
    if (error != null) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(error)));
    }
  }
}
