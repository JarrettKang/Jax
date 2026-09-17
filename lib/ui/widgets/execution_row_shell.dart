import 'package:flutter/material.dart';

import '../theme/home_pilot_theme.dart';
import '../theme/list_density.dart';

/// Visual state only. Sources retain all eligibility and execution callbacks.
enum ExecutionVisualState { idle, running, paused, waiting, completed }

extension ExecutionVisualPresentation on ExecutionVisualState {
  String get label => switch (this) {
    ExecutionVisualState.idle => '',
    ExecutionVisualState.running => '正在执行',
    ExecutionVisualState.paused => '已暂停',
    ExecutionVisualState.waiting => '等待中',
    ExecutionVisualState.completed => '已完成',
  };
  IconData? get icon => switch (this) {
    ExecutionVisualState.idle => null,
    ExecutionVisualState.running => Icons.play_arrow,
    ExecutionVisualState.paused => Icons.pause,
    ExecutionVisualState.waiting => Icons.hourglass_empty,
    ExecutionVisualState.completed => Icons.check,
  };
}

/// Presentation slots, with no Event/Routine/PlanItem dependencies.
class ExecutionRowShell extends StatefulWidget {
  const ExecutionRowShell({
    required this.title,
    required this.state,
    required this.actions,
    this.density = JaxListDensity.standard,
    this.trailing,
    this.metadata,
    this.time,
    super.key,
  });
  final JaxListDensity density;
  final Widget? trailing;
  final String title;
  final ExecutionVisualState state;
  final Widget? metadata, time;
  final List<Widget> actions;
  @override
  State<ExecutionRowShell> createState() => _ExecutionRowShellState();
}

class _ExecutionRowShellState extends State<ExecutionRowShell> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    final compact = widget.density == JaxListDensity.compact;
    final running = widget.state == ExecutionVisualState.running;
    final text = Theme.of(context).textTheme;
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.title, style: text.titleMedium),
        if (widget.metadata != null) ...[
          const SizedBox(height: 4),
          DefaultTextStyle(
            style: text.bodySmall!.copyWith(
              color: running ? HomePilot.textSecondary : HomePilot.textMuted,
            ),
            child: widget.metadata!,
          ),
        ],
        if (widget.state.label.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            widget.state.label,
            style: text.bodySmall!.copyWith(
              color: running ? HomePilot.accent : HomePilot.textMuted,
            ),
          ),
        ],
      ],
    );
    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ...widget.actions,
        if (widget.trailing != null) widget.trailing!,
      ],
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        decoration: BoxDecoration(
          color: running
              ? HomePilot.accentSubtle
              : _hovered
              ? HomePilot.surfaceSubtle
              : null,
          border: Border(
            left: BorderSide(
              color: running ? HomePilot.accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: LayoutBuilder(
          builder: (context, box) {
            final wide =
                box.maxWidth >= 880 &&
                MediaQuery.textScalerOf(context).scale(16) <= 20;
            final marker = SizedBox(
              width: 24,
              child: widget.state.icon == null
                  ? null
                  : Icon(
                      widget.state.icon,
                      size: 16,
                      color: running ? HomePilot.accent : HomePilot.textMuted,
                    ),
            );
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  marker,
                  Expanded(child: info),
                  const SizedBox(width: 16),
                  SizedBox(width: 108, child: widget.time),
                  const SizedBox(width: 16),
                  SizedBox(width: 344, child: actions),
                ],
              );
            }
            // Keep the 48dp control beside content only at modest text scales.
            // Multiple actions and enlarged text retain the wrapping action row.
            final inlineAction =
                compact &&
                widget.actions.length == 1 &&
                box.maxWidth >= 300 &&
                MediaQuery.textScalerOf(context).scale(16) <= 20;
            final side = compact ? widget.trailing : null;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.time != null)
                  Padding(
                    padding: EdgeInsets.only(left: 24, bottom: compact ? 4 : 8),
                    child: widget.time,
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: marker,
                    ),
                    Expanded(child: info),
                    if (inlineAction) ...[
                      const SizedBox(width: 8),
                      SizedBox(width: 96, child: widget.actions.single),
                    ],
                    if (side != null) ...[const SizedBox(width: 4), side],
                  ],
                ),
                if ((!inlineAction && widget.actions.isNotEmpty) ||
                    (!compact && widget.trailing != null)) ...[
                  SizedBox(height: compact ? 4 : 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: compact
                        ? Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.end,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: widget.actions,
                          )
                        : actions,
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class ExecutionTimeLabel extends StatelessWidget {
  const ExecutionTimeLabel(this.value, {this.caption, super.key});
  final String value;
  final String? caption;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
      ),
      if (caption != null)
        Text(
          caption!,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: HomePilot.textSecondary),
        ),
    ],
  );
}

String executionDurationLabel(Duration value) =>
    '${value.inHours.toString().padLeft(2, '0')}:${value.inMinutes.remainder(60).toString().padLeft(2, '0')}:${value.inSeconds.remainder(60).toString().padLeft(2, '0')}';
String routineClockLabel(int minute, {int? relativeTo}) =>
    '${relativeTo != null && minute < relativeTo ? '次日 ' : ''}${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
