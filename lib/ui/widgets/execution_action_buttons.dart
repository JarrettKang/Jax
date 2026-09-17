import 'package:flutter/material.dart';

/// Presentation-only actions shared by Event and Routine execution surfaces.
enum ExecutionAction { start, resume, pause, wait, continueWaiting, complete }

extension on ExecutionAction {
  String get label => switch (this) {
    ExecutionAction.start => '开始',
    ExecutionAction.resume => '恢复',
    ExecutionAction.pause => '暂停',
    ExecutionAction.wait => '等待',
    ExecutionAction.continueWaiting => '继续',
    ExecutionAction.complete => '完成',
  };

  IconData get icon => switch (this) {
    ExecutionAction.start ||
    ExecutionAction.resume ||
    ExecutionAction.continueWaiting => Icons.play_arrow,
    ExecutionAction.wait => Icons.hourglass_empty,
    ExecutionAction.pause => Icons.pause,
    ExecutionAction.complete => Icons.check,
  };

  bool get isPrimary => this == ExecutionAction.complete;
}

/// A compact, touch-friendly high-frequency execution control.
class ExecutionActionButton extends StatelessWidget {
  const ExecutionActionButton({
    required this.action,
    required this.onPressed,
    this.primary,
    this.style,
    this.label,
    super.key,
  });

  final ExecutionAction action;
  final VoidCallback? onPressed;

  /// Optional scene-specific visual priority; existing callers keep defaults.
  final bool? primary;
  final ButtonStyle? style;
  final String? label;

  static const _style = ButtonStyle(
    minimumSize: WidgetStatePropertyAll(Size(0, 44)),
    padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
    visualDensity: VisualDensity.compact,
  );

  @override
  Widget build(BuildContext context) {
    final button = (primary ?? action.isPrimary)
        ? FilledButton.icon(
            onPressed: onPressed,
            style: style ?? _style,
            icon: Icon(action.icon, size: 18),
            label: Text(label ?? action.label),
          )
        : OutlinedButton.icon(
            onPressed: onPressed,
            style: style ?? _style,
            icon: Icon(action.icon, size: 18),
            label: Text(label ?? action.label),
          );
    return Tooltip(message: label ?? action.label, child: button);
  }
}

/// Keeps paired high-frequency actions separated on desktop and touch screens.
class ExecutionActionRow extends StatelessWidget {
  const ExecutionActionRow({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: children,
  );
}
