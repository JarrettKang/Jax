import '../theme/desktop_polish.dart';
import '../theme/list_density.dart';
import '../widgets/paused_routine_row.dart';
import '../../core/entities/execution_capabilities.dart';

import 'dart:async';

import '../../core/services/temporal_routine.dart';
import '../controllers/today_temporal_view.dart';

import 'package:flutter/material.dart';

import '../../core/entities/category.dart';
import '../../core/entities/event_status.dart';
import '../../core/entities/jax_event.dart';
import '../../core/entities/plan_item.dart';
import '../../core/entities/routine.dart';
import '../controllers/event_controller.dart';
import '../controllers/planning_controller.dart';
import '../theme/operational_theme.dart';
import '../theme/home_pilot_theme.dart';
import '../widgets/execution_row_shell.dart';
import '../widgets/execution_action_buttons.dart';
import '../widgets/waiting_routine_row.dart';
import '../widgets/event_more_menu_button.dart';
import '../widgets/standalone_event_dialog.dart';

class EventsPage extends StatefulWidget {
  const EventsPage({
    required this.controller,
    this.planningController,
    super.key,
  });
  final EventController controller;
  final PlanningController? planningController;

  @override
  State<EventsPage> createState() => _EventsPageState();
}

class _EventsPageState extends State<EventsPage> with WidgetsBindingObserver {
  List<String>? _transitionOrder;
  Timer? _boundaryTimer;
  DateTime? _scheduledBoundary;
  TodayTemporalView _temporal() => TodayTemporalView.derive(
    routines: widget.controller.routines,
    day: widget.controller.currentJaxDay,
    time: widget.controller.currentTime,
    executionFor: widget.controller.executionForOccurrence,
    runningRoutineId: widget.controller.runningRoutine?.id,
    waitingRoutineIds: {
      ...widget.controller.waitingRoutines.map((r) => r.id),
      ...widget.controller.pausedRoutineExecutions.map((e) => e.routineId),
    },
  );
  void _scheduleBoundary() {
    final boundary = _temporal().nextBoundary;
    if (boundary == _scheduledBoundary && _boundaryTimer?.isActive == true) {
      return;
    }
    _boundaryTimer?.cancel();
    _scheduledBoundary = boundary;
    if (boundary == null) return;
    _boundaryTimer = Timer(
      boundary.difference(widget.controller.currentTime),
      () {
        if (!mounted) return;
        _scheduledBoundary = null;
        setState(() {});
        _scheduleBoundary();
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.controller.load();
      widget.planningController?.load();
      _scheduleBoundary();
    }
  }

  @override
  void didUpdateWidget(EventsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_scheduleBoundary);
      widget.controller.addListener(_scheduleBoundary);
    }
    _scheduleBoundary();
  }

  @override
  void dispose() {
    _boundaryTimer?.cancel();
    widget.controller.removeListener(_scheduleBoundary);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    widget.planningController?.load();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_scheduleBoundary);
    _scheduleBoundary();
  }

  @override
  Widget build(BuildContext context) => OperationalVisualScope(
    builder: (context) => ColoredBox(
      color: HomePilot.canvas,
      child: AnimatedBuilder(
        animation: Listenable.merge([
          widget.controller,
          if (widget.planningController != null) widget.planningController!,
        ]),
        builder: (context, _) {
          final controller = widget.controller;
          final planning = widget.planningController;
          if ((controller.loading || planning?.loading == true) &&
              controller.todayEvents.isEmpty &&
              (planning?.projectedTodayItems.isEmpty ?? true)) {
            return const Center(child: CircularProgressIndicator());
          }
          final events = [
            for (final event in controller.todayEvents)
              if (event.status != EventStatus.completed) event,
            if (controller.runningEvent != null &&
                !controller.todayEvents.any(
                  (e) => e.id == controller.runningEvent!.id,
                ))
              controller.runningEvent!,
          ];
          // Suppress only when the replacement can actually render, including a
          // running Event loaded before its EventDayPlan during the start transaction.
          final linked = events.map((e) => e.sourcePlanItemId).toSet();
          final projected = (planning?.projectedTodayItems ?? <PlanItem>[])
              .where((item) => !linked.contains(item.id))
              .toList();
          final persistentEvents = events
              .where((e) => e.status != EventStatus.running)
              .toList();
          final rows = <String, Widget>{
            for (final event in persistentEvents)
              _eventIdentity(event): _EventRow(
                key: ValueKey(_eventIdentity(event)),
                controller: controller,
                planning: planning,
                event: event,
                index: controller.todayEvents.indexWhere(
                  (e) => e.id == event.id,
                ),
                count: controller.todayEvents.length,
                onReorder: () => setState(() => _transitionOrder = null),
                allowUp: persistentEvents.indexOf(event) > 0,
                allowDown:
                    persistentEvents.indexOf(event) <
                    persistentEvents.length - 1,
                upTarget: persistentEvents.indexOf(event) > 0
                    ? controller.todayEvents.indexWhere(
                        (e) =>
                            e.id ==
                            persistentEvents[persistentEvents.indexOf(event) -
                                    1]
                                .id,
                      )
                    : null,
                downTarget:
                    persistentEvents.indexOf(event) <
                        persistentEvents.length - 1
                    ? controller.todayEvents.indexWhere(
                        (e) =>
                            e.id ==
                            persistentEvents[persistentEvents.indexOf(event) +
                                    1]
                                .id,
                      )
                    : null,
              ),
            for (final item in projected)
              'plan-${item.id}': _TodayExecutionRow(
                key: ValueKey('plan-${item.id}'),
                name: item.title,
                secondary:
                    planning!.plans
                        .where((p) => p.id == item.planId)
                        .map((p) => planning.nodeFor(p.worldNodeId)?.name ?? '')
                        .firstOrNull ??
                    '',
                status: '',
                statusKind: _TodayStatusKind.unstarted,
                actions: [
                  ExecutionActionButton(
                    key: ValueKey('today-plan-start-${item.id}'),
                    action: ExecutionAction.start,
                    primary: false,
                    style: HomePilot.buttonStyle(outlined: true),
                    onPressed: planning.startingPlanItem
                        ? null
                        : () => _startPlanItem(item),
                  ),
                ],
              ),
          };
          final order = [
            ...?_transitionOrder?.where(rows.containsKey),
            ...rows.keys.where(
              (id) => !(_transitionOrder?.contains(id) ?? false),
            ),
          ];
          final temporal = _temporal();
          final ordinary = controller.todayRoutines
              .where(
                (r) =>
                    !controller.waitingRoutines.any((w) => w.id == r.id) &&
                    !controller.pausedRoutineExecutions.any(
                      (e) => e.routineId == r.id,
                    ) &&
                    r.timeRecommendation == null &&
                    controller.executionFor(r)?.status !=
                        RoutineExecutionStatus.completed &&
                    controller.executionFor(r)?.status !=
                        RoutineExecutionStatus.running,
              )
              .toList();
          final running = <Widget>[
            for (final event in events.where(
              (e) => e.status == EventStatus.running,
            ))
              _EventRow(
                key: ValueKey(_eventIdentity(event)),
                controller: controller,
                planning: planning,
                event: event,
                index: 0,
                count: 1,
              ),
            if (controller.runningRoutine != null)
              _RoutineRow(
                controller: controller,
                routine: controller.runningRoutine!,
              ),
          ];
          Widget temporalRow(TodayTemporalEntry entry) => _RoutineRow(
            key: ValueKey(entry.identity),
            controller: controller,
            routine: entry.routine,
            temporal: entry,
          );
          List<Widget> section(
            String title,
            String key,
            List<Widget> children,
          ) => children.isEmpty
              ? []
              : [
                  const SizedBox(height: 16),
                  _SectionHeader(title: title),
                  Container(
                    key: ValueKey(key),
                    child: _ExecutionList(children: children),
                  ),
                ];
          final day = controller.currentJaxDay;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: ListView(
                key: const ValueKey('dynamic-today'),
                padding: OperationalTheme.pagePadding(context),
                children: [
                  Text('今日', style: Theme.of(context).textTheme.headlineMedium),
                  Text(
                    '${day.displayDate.month}月${day.displayDate.day}日',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Wrap(
                    alignment: WrapAlignment.end,
                    children: [
                      TextButton.icon(
                        key: const ValueKey('today-add-existing'),
                        onPressed: () => _addExisting(context),
                        icon: const Icon(Icons.playlist_add, size: 18),
                        label: const Text('已有事项'),
                      ),
                      TextButton.icon(
                        key: const ValueKey('add-standalone-event'),
                        onPressed: () => _createStandalone(context),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('临时事项'),
                      ),
                    ],
                  ),
                  ...section('正在进行', 'today-running', running),
                  ...section('现在需要处理', 'today-now', [
                    for (final e in temporal.now) temporalRow(e),
                  ]),
                  ...section('持续事项', 'today-persistent', [
                    for (final e in controller.pausedRoutineExecutions)
                      PausedRoutineRow(
                        key: ValueKey('today-paused-${e.id}'),
                        operationalVisuals: true,
                        controller: controller,
                        execution: e,
                      ),
                    for (final e in controller.waitingRoutineExecutions)
                      WaitingRoutineRow(
                        key: ValueKey('today-waiting-${e.id}'),
                        operationalVisuals: true,
                        controller: controller,
                        execution: e,
                      ),
                    for (final id in order) rows[id]!,
                    for (final routine in ordinary)
                      _RoutineRow(controller: controller, routine: routine),
                  ]),
                  ...section('稍后', 'today-later', [
                    for (final e in temporal.later) temporalRow(e),
                  ]),
                  if (running.isEmpty &&
                      rows.isEmpty &&
                      ordinary.isEmpty &&
                      controller.waitingRoutineExecutions.isEmpty &&
                      controller.pausedRoutineExecutions.isEmpty &&
                      temporal.now.isEmpty &&
                      temporal.later.isEmpty)
                    const _CompactEmptyState(text: '当前没有待处理事项'),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );

  Future<void> _createStandalone(BuildContext context) async {
    final result = await showStandaloneEventDialog(context, widget.controller);
    if (result == null) return;
    final error = await widget.controller.createStandaloneForToday(
      result.$1,
      categoryId: result.$2,
    );
    if (error != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  String _eventIdentity(JaxEvent event) => event.sourcePlanItemId == null
      ? 'event-${event.id}'
      : 'plan-${event.sourcePlanItemId}';

  Future<void> _startPlanItem(PlanItem item) async {
    final planning = widget.planningController!;
    _transitionOrder ??= [
      ...widget.controller.todayEvents.map(_eventIdentity),
      ...planning.projectedTodayItems.map((i) => 'plan-${i.id}'),
    ];
    try {
      await planning.startPlanItem(
        item.id,
        refreshExecution: widget.controller.load,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _addExisting(BuildContext context) async {
    final candidates = widget.controller.events
        .where(
          (event) =>
              event.status != EventStatus.completed &&
              !widget.controller.isPlannedToday(event.id),
        )
        .toList(growable: false);
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('没有可重新加入今日的事项')));
      return;
    }
    final chosen = <String>{};
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          constraints: DesktopPolish.dialog(
            dialogContext,
            DesktopDialogSize.form,
          ),
          title: const Text('已有事项'),
          content: SizedBox(
            width: 480,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final event in candidates)
                  CheckboxListTile(
                    key: ValueKey('existing-event-${event.id}'),
                    value: chosen.contains(event.id),
                    title: Text(event.name),
                    subtitle: Text(event.isPlanned ? '已派发事项' : '临时事项'),
                    onChanged: (value) => setDialogState(() {
                      value == true
                          ? chosen.add(event.id)
                          : chosen.remove(event.id);
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: chosen.isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: const Text('加入今日'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true) return;
    final error = await widget.controller.addManyToToday(chosen);
    if (error != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(title, style: Theme.of(context).textTheme.titleLarge),
  );
}

class _ExecutionList extends StatelessWidget {
  const _ExecutionList({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var i = 0; i < children.length; i++) ...[children[i]],
    ],
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
    super.key,
    this.onReorder,
    this.allowUp = false,
    this.allowDown = false,
    this.upTarget,
    this.downTarget,
    required this.controller,
    required this.planning,
    required this.event,
    required this.index,
    required this.count,
  });
  final EventController controller;
  final PlanningController? planning;
  final VoidCallback? onReorder;
  final JaxEvent event;
  final bool allowUp, allowDown;
  final int? upTarget, downTarget;
  final int index;
  final int count;

  @override
  Widget build(BuildContext context) {
    final category = _category();
    return _TodayExecutionRow(
      key: ValueKey('today-event-${event.id}'),
      name: event.name,
      secondary:
          planning?.plans
              .where(
                (p) => planning!
                    .itemsFor(p.id)
                    .any((i) => i.id == event.sourcePlanItemId),
              )
              .map((p) => planning!.nodeFor(p.worldNodeId)?.name)
              .firstOrNull ??
          category?.name ??
          '临时事项',
      status: _status(event),
      time: event.status == EventStatus.running
          ? ExecutionTimeLabel(
              executionDurationLabel(controller.elapsedFor(event)),
              caption: '主动用时',
            )
          : null,
      statusKind: switch (event.status) {
        EventStatus.pending => _TodayStatusKind.unstarted,
        EventStatus.running => _TodayStatusKind.running,
        EventStatus.paused => _TodayStatusKind.paused,
        EventStatus.waiting => _TodayStatusKind.waiting,
        EventStatus.completed => _TodayStatusKind.completed,
      },

      actions: [
        if (allowUp)
          IconButton(
            key: ValueKey('today-up-${event.id}'),
            tooltip: '今日上移',
            onPressed: () {
              onReorder?.call();
              controller.moveToday(event.id, upTarget!);
            },
            icon: const Icon(Icons.arrow_upward),
          ),
        if (allowDown)
          IconButton(
            key: ValueKey('today-down-${event.id}'),
            tooltip: '今日下移',
            onPressed: () {
              onReorder?.call();
              controller.moveToday(event.id, downTarget!);
            },
            icon: const Icon(Icons.arrow_downward),
          ),
        ..._actions(context),
        if (planning?.canWithdrawEvent(event.id) == true &&
            event.status == EventStatus.pending &&
            event.firstStartedAt == null &&
            event.completedAt == null &&
            !controller.hasEventRunSegments(event.id))
          EventMoreMenuButton<String>(
            key: ValueKey('today-event-more-${event.id}'),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'withdraw', child: Text('收回到计划')),
            ],
            onSelected: (_) async {
              try {
                await planning!.withdrawToPlan(event.sourcePlanItemId!);
                await controller.load();
              } catch (error) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(error.toString())));
                }
              }
            },
          ),
        if (controller.canDeferToday(event))
          EventMoreMenuButton<String>(
            key: ValueKey('today-defer-more-${event.id}'),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'defer', child: Text('今天先不处理')),
            ],
            onSelected: (_) async {
              final error = await controller.removeFromToday(event.id);
              if (error != null && context.mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(error)));
              }
            },
          ),
      ],
    );
  }

  Category? _category() {
    return controller.categories
        .where((c) => c.id == controller.effectiveCategoryIdFor(event.id))
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
      if (event.status.canComplete)
        _button(
          context,
          'complete',
          ExecutionAction.complete,
          () => controller.complete(event.id),
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
    label: action == ExecutionAction.resume ? '继续' : null,
    primary: action == ExecutionAction.pause,
    style: HomePilot.buttonStyle(
      outlined: action != ExecutionAction.pause,
      primary: action == ExecutionAction.pause,
    ),
    onPressed: () async {
      final error = await callback();
      if (error != null && context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error)));
      }
    },
  );

  String _status(JaxEvent event) => switch (event.status) {
    EventStatus.pending => '',
    EventStatus.running => '正在执行',
    EventStatus.paused => '已暂停',
    EventStatus.waiting => '等待中',
    EventStatus.completed => '已完成',
  };
}

class _RoutineRow extends StatelessWidget {
  const _RoutineRow({
    required this.controller,
    required this.routine,
    this.temporal,
    super.key,
  });
  final TodayTemporalEntry? temporal;
  final EventController controller;
  final Routine routine;
  @override
  Widget build(BuildContext context) {
    final execution = temporal == null
        ? controller.executionFor(routine)
        : temporal!.execution;
    final category = controller.routineCategories
        .where((c) => c.id == routine.routineCategoryId)
        .firstOrNull;
    return _TodayExecutionRow(
      key: ValueKey('today-routine-${routine.id}'),
      name: routine.name,
      secondary: temporal == null
          ? '${category?.name ?? '未分类'} · ${_recurrence(routine.recurrence)}'
          : switch (temporal!.state) {
              TemporalRecommendationState.active =>
                '理想完成前 ${_windowTime(temporal!.window.idealEndDateTime)}',
              TemporalRecommendationState.overdue =>
                '已超过理想时间 · 最晚 ${_windowTime(temporal!.window.latestEndDateTime)}',
              _ =>
                '${category?.name ?? '未分类'} · ${_recurrence(routine.recurrence)}',
            },
      status: _status(execution),
      warning: temporal?.state == TemporalRecommendationState.overdue,
      time: execution?.status == RoutineExecutionStatus.running
          ? ExecutionTimeLabel(
              executionDurationLabel(controller.routineElapsed(routine)),
              caption: '主动用时',
            )
          : temporal?.state == TemporalRecommendationState.inactive
          ? ExecutionTimeLabel(
              _time(temporal!.window.startDateTime),
              caption: '开始推荐',
            )
          : null,
      statusKind: switch (execution?.status) {
        null => _TodayStatusKind.unstarted,
        RoutineExecutionStatus.running => _TodayStatusKind.running,
        RoutineExecutionStatus.paused => _TodayStatusKind.paused,
        RoutineExecutionStatus.waiting => _TodayStatusKind.waiting,
        RoutineExecutionStatus.completed => _TodayStatusKind.completed,
      },

      actions: switch (execution?.status) {
        null => [
          _button(
            context,
            'start',
            ExecutionAction.start,
            () => temporal == null
                ? controller.startRoutine(routine)
                : controller.startRoutineOccurrence(
                    routine,
                    temporal!.window.occurrenceKey,
                  ),
          ),
        ],
        RoutineExecutionStatus.running => [
          _button(
            context,
            'wait',
            ExecutionAction.wait,
            () => controller.waitRoutine(routine),
          ),
          _button(
            context,
            'pause',
            ExecutionAction.pause,
            () => temporal == null
                ? controller.pauseRoutine(routine)
                : controller.pauseRoutineOccurrence(
                    routine,
                    temporal!.window.occurrenceKey,
                  ),
          ),
          _button(
            context,
            'complete',
            ExecutionAction.complete,
            () => temporal == null
                ? controller.completeRoutine(routine)
                : controller.completeRoutineOccurrence(
                    routine,
                    temporal!.window.occurrenceKey,
                  ),
          ),
        ],
        RoutineExecutionStatus.paused || RoutineExecutionStatus.waiting => [
          _button(
            context,
            'resume',
            ExecutionAction.resume,
            () => temporal == null
                ? controller.startRoutine(routine)
                : controller.startRoutineOccurrence(
                    routine,
                    temporal!.window.occurrenceKey,
                  ),
          ),
          _button(
            context,
            'complete',
            ExecutionAction.complete,
            () => temporal == null
                ? controller.completeRoutine(routine)
                : controller.completeRoutineOccurrence(
                    routine,
                    temporal!.window.occurrenceKey,
                  ),
          ),
        ],
        RoutineExecutionStatus.completed => const [],
      },
    );
  }

  Widget _button(
    BuildContext context,
    String keyName,
    ExecutionAction action,
    Future<String?> Function() callback,
  ) => ExecutionActionButton(
    key: ValueKey('today-routine-$keyName-${routine.id}'),
    action: action,
    label: action == ExecutionAction.resume ? '继续' : null,
    primary: action == ExecutionAction.pause,
    style: HomePilot.buttonStyle(
      outlined: action != ExecutionAction.pause,
      primary: action == ExecutionAction.pause,
    ),
    onPressed: () async {
      final error = await callback();
      if (error != null && context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error)));
      }
    },
  );
  String _windowTime(DateTime t) =>
      '${DateUtils.isSameDay(t, temporal!.window.startDateTime) ? '' : '次日 '}${_time(t)}';
  String _time(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  String _status(RoutineExecution? execution) => switch (execution?.status) {
    null => '',
    RoutineExecutionStatus.running => '正在执行',
    RoutineExecutionStatus.paused => '已暂停',
    RoutineExecutionStatus.waiting => '等待中',
    RoutineExecutionStatus.completed => '已完成',
  };
  String _recurrence(RoutineRecurrence recurrence) => switch (recurrence) {
    RoutineRecurrence.daily => '每日',
    RoutineRecurrence.weekdays => '工作日',
    RoutineRecurrence.weekends => '周末',
    RoutineRecurrence.selectedWeekdays => '指定星期',
  };
}

enum _TodayStatusKind { unstarted, running, paused, waiting, completed }

class _TodayExecutionRow extends StatelessWidget {
  const _TodayExecutionRow({
    required this.name,
    required this.secondary,
    required this.status,
    required this.statusKind,
    required this.actions,
    this.warning = false,
    this.time,
    super.key,
  });
  final String name, secondary, status;
  final _TodayStatusKind statusKind;
  final List<Widget> actions;
  final bool warning;
  final Widget? time;
  @override
  Widget build(BuildContext context) => ExecutionRowShell(
    density: JaxListDensity.compact,
    title: name,
    state: switch (statusKind) {
      _TodayStatusKind.unstarted => ExecutionVisualState.idle,
      _TodayStatusKind.running => ExecutionVisualState.running,
      _TodayStatusKind.paused => ExecutionVisualState.paused,
      _TodayStatusKind.waiting => ExecutionVisualState.waiting,
      _TodayStatusKind.completed => ExecutionVisualState.completed,
    },
    metadata: secondary.isEmpty
        ? null
        : Text(
            secondary,
            style: warning ? const TextStyle(color: HomePilot.warning) : null,
          ),
    time: time,
    actions: actions,
  );
}
