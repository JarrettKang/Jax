import 'package:flutter/material.dart';

import '../../core/entities/category.dart';
import '../../core/entities/event_status.dart';
import '../../core/entities/jax_event.dart';
import '../../core/entities/routine.dart';
import '../controllers/event_controller.dart';
import '../theme/category_palette_colors.dart';
import '../widgets/execution_action_buttons.dart';

class EventsPage extends StatelessWidget {
  const EventsPage({
    required this.controller,
    required this.onOpenWorld,
    super.key,
  });
  final EventController controller;
  final VoidCallback onOpenWorld;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      if (controller.loading) {
        return const Center(child: CircularProgressIndicator());
      }
      final events = controller.todayEvents;
      final routines = controller.todayRoutines;
      final day = controller.currentJaxDay;
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 72),
            children: [
              Text('今日', style: Theme.of(context).textTheme.headlineMedium),
              Text(
                '${day.displayDate.month}月${day.displayDate.day}日 · 23:00 结束',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 22),
              _SectionHeader(title: '今日事项', count: events.length),
              if (events.isEmpty)
                _EventEmptyState(onOpenWorld: onOpenWorld)
              else
                _ExecutionList(
                  children: [
                    for (var i = 0; i < events.length; i++)
                      _EventRow(
                        controller: controller,
                        event: events[i],
                        index: i,
                        count: events.length,
                      ),
                  ],
                ),
              const SizedBox(height: 20),
              _SectionHeader(title: '今日日常', count: routines.length),
              if (routines.isEmpty)
                const _CompactEmptyState(text: '今天没有符合 recurrence 的日常')
              else
                _ExecutionList(
                  children: [
                    for (final routine in routines)
                      _RoutineRow(controller: controller, routine: routine),
                  ],
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count});
  final String title;
  final int count;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(width: 8),
        Text('$count', style: Theme.of(context).textTheme.labelSmall),
      ],
    ),
  );
}

class _ExecutionList extends StatelessWidget {
  const _ExecutionList({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var i = 0; i < children.length; i++) ...[
        children[i],
        if (i < children.length - 1) const Divider(height: 1),
      ],
    ],
  );
}

class _EventEmptyState extends StatelessWidget {
  const _EventEmptyState({required this.onOpenWorld});
  final VoidCallback onOpenWorld;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            '暂无今日事项',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        TextButton.icon(
          key: const ValueKey('today-open-world'),
          onPressed: onOpenWorld,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('从世界添加'),
        ),
      ],
    ),
  );
}

class _CompactEmptyState extends StatelessWidget {
  const _CompactEmptyState({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}

class _EventRow extends StatelessWidget {
  const _EventRow({
    required this.controller,
    required this.event,
    required this.index,
    required this.count,
  });
  final EventController controller;
  final JaxEvent event;
  final int index;
  final int count;

  @override
  Widget build(BuildContext context) {
    final breadcrumb = controller.eventBreadcrumb(event);
    final category = _category();
    final secondary = [
      if (category != null) category.name,
      if (breadcrumb.isNotEmpty) breadcrumb,
    ].join(' · ');
    return _TodayExecutionRow(
      key: ValueKey('today-event-${event.id}'),
      name: event.name,
      secondary: secondary.isEmpty ? '未分类' : secondary,
      status: _status(event),
      colorKey: category?.colorKey,
      running: event.status == EventStatus.running,
      actions: [
        if (index > 0)
          IconButton(
            key: ValueKey('today-up-${event.id}'),
            tooltip: '今日上移',
            onPressed: () => controller.moveToday(event.id, index - 1),
            icon: const Icon(Icons.arrow_upward),
          ),
        if (index < count - 1)
          IconButton(
            key: ValueKey('today-down-${event.id}'),
            tooltip: '今日下移',
            onPressed: () => controller.moveToday(event.id, index + 1),
            icon: const Icon(Icons.arrow_downward),
          ),
        ..._actions(context),
        if (event.status != EventStatus.running &&
            event.status != EventStatus.completed)
          IconButton(
            key: ValueKey('today-remove-${event.id}'),
            tooltip: '移出今日',
            onPressed: () => controller.removeFromToday(event.id),
            icon: const Icon(Icons.today_outlined),
          ),
      ],
    );
  }

  Category? _category() {
    final byId = {for (final item in controller.worldEvents) item.id: item};
    var root = event;
    final seen = <String>{};
    while (root.parentEventId != null && seen.add(root.id)) {
      final parent = byId[root.parentEventId];
      if (parent == null) break;
      root = parent;
    }
    return controller.categories
        .where((c) => c.id == root.categoryId)
        .firstOrNull;
  }

  List<Widget> _actions(BuildContext context) => switch (event.status) {
    EventStatus.pending => [
      _button(
        context,
        'start',
        ExecutionAction.start,
        () => controller.start(event.id),
      ),
    ],
    EventStatus.paused => [
      _button(
        context,
        'resume',
        ExecutionAction.resume,
        () => controller.resume(event.id),
      ),
    ],
    EventStatus.running => [
      _button(
        context,
        'pause',
        ExecutionAction.pause,
        () => controller.pause(event.id),
      ),
      _button(
        context,
        'complete',
        ExecutionAction.complete,
        () => controller.complete(event.id),
      ),
    ],
    EventStatus.waiting => [
      _button(
        context,
        'resume',
        ExecutionAction.resume,
        () => controller.resume(event.id),
      ),
      _button(
        context,
        'complete',
        ExecutionAction.complete,
        () => controller.complete(event.id),
      ),
    ],
    EventStatus.completed => const [],
  };

  Widget _button(
    BuildContext context,
    String keyName,
    ExecutionAction action,
    Future<String?> Function() callback,
  ) => ExecutionActionButton(
    key: ValueKey('$keyName-${event.id}'),
    action: action,
    onPressed: () async {
      final error = await callback();
      if (error != null && context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error)));
      }
    },
  );

  String _status(JaxEvent event) => switch (event.status) {
    EventStatus.pending => '未开始',
    EventStatus.running => '正在执行',
    EventStatus.paused => '已暂停',
    EventStatus.waiting => '等待中',
    EventStatus.completed => '已完成',
  };
}

class _RoutineRow extends StatelessWidget {
  const _RoutineRow({required this.controller, required this.routine});
  final EventController controller;
  final Routine routine;
  @override
  Widget build(BuildContext context) {
    final execution = controller.executionFor(routine);
    final category = controller.routineCategories
        .where((c) => c.id == routine.routineCategoryId)
        .firstOrNull;
    return _TodayExecutionRow(
      key: ValueKey('today-routine-${routine.id}'),
      name: routine.name,
      secondary:
          '${category?.name ?? '未分类'} · ${_recurrence(routine.recurrence)}',
      status: _status(execution),
      colorKey: category?.colorKey,
      running: execution?.status == RoutineExecutionStatus.running,
      actions: switch (execution?.status) {
        null => [
          _button(
            'start',
            ExecutionAction.start,
            () => controller.startRoutine(routine),
          ),
        ],
        RoutineExecutionStatus.running => [
          _button(
            'pause',
            ExecutionAction.pause,
            () => controller.pauseRoutine(routine),
          ),
          _button(
            'complete',
            ExecutionAction.complete,
            () => controller.completeRoutine(routine),
          ),
        ],
        RoutineExecutionStatus.paused => [
          _button(
            'resume',
            ExecutionAction.resume,
            () => controller.startRoutine(routine),
          ),
          _button(
            'complete',
            ExecutionAction.complete,
            () => controller.completeRoutine(routine),
          ),
        ],
        RoutineExecutionStatus.completed => const [],
      },
    );
  }

  Widget _button(
    String keyName,
    ExecutionAction action,
    VoidCallback callback,
  ) => ExecutionActionButton(
    key: ValueKey('today-routine-$keyName-${routine.id}'),
    action: action,
    onPressed: callback,
  );
  String _status(RoutineExecution? execution) => switch (execution?.status) {
    null => '未开始',
    RoutineExecutionStatus.running => '正在执行',
    RoutineExecutionStatus.paused => '已暂停',
    RoutineExecutionStatus.completed => '已完成',
  };
  String _recurrence(RoutineRecurrence recurrence) => switch (recurrence) {
    RoutineRecurrence.daily => '每日',
    RoutineRecurrence.weekdays => '工作日',
    RoutineRecurrence.weekends => '周末',
    RoutineRecurrence.selectedWeekdays => '指定星期',
  };
}

class _TodayExecutionRow extends StatefulWidget {
  const _TodayExecutionRow({
    required this.name,
    required this.secondary,
    required this.status,
    required this.running,
    required this.actions,
    this.colorKey,
    super.key,
  });
  final String name;
  final String secondary;
  final String status;
  final int? colorKey;
  final bool running;
  final List<Widget> actions;
  @override
  State<_TodayExecutionRow> createState() => _TodayExecutionRowState();
}

class _TodayExecutionRowState extends State<_TodayExecutionRow> {
  var hovering = false;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final accent = widget.colorKey == null
        ? CategoryPaletteColors.neutral(context)
        : CategoryPaletteColors.resolve(context, widget.colorKey!);
    return MouseRegion(
      onEnter: (_) => setState(() => hovering = true),
      onExit: (_) => setState(() => hovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        decoration: BoxDecoration(
          color: widget.running
              ? accent.withValues(alpha: .10)
              : hovering
              ? colors.surfaceContainerHighest.withValues(alpha: .55)
              : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: widget.running ? accent : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final info = _info(context, accent);
            final status = _StatusLabel(
              text: widget.status,
              running: widget.running,
            );
            if (constraints.maxWidth >= 700) {
              return Row(
                children: [
                  Expanded(child: info),
                  const SizedBox(width: 20),
                  SizedBox(width: 88, child: status),
                  const SizedBox(width: 12),
                  Wrap(spacing: 8, runSpacing: 6, children: widget.actions),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                info,
                const SizedBox(height: 7),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    status,
                    const SizedBox(width: 8),
                    Expanded(
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 8,
                        runSpacing: 6,
                        children: widget.actions,
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _info(BuildContext context, Color accent) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        widget.name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: widget.running ? FontWeight.w700 : FontWeight.w600,
        ),
      ),
      const SizedBox(height: 2),
      Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              widget.secondary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    ],
  );
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.text, required this.running});
  final String text;
  final bool running;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        running ? Icons.play_circle_fill : Icons.circle_outlined,
        size: 13,
        color: running
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.outline,
      ),
      const SizedBox(width: 5),
      Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          fontWeight: running ? FontWeight.w700 : FontWeight.w400,
          color: running ? Theme.of(context).colorScheme.primary : null,
        ),
      ),
    ],
  );
}
