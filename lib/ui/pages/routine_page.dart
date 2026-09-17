import '../theme/desktop_polish.dart';
import '../theme/list_density.dart';
import '../../core/entities/execution_capabilities.dart';

import 'package:flutter/material.dart';

import '../../core/entities/routine.dart';
import '../../core/entities/routine_category.dart';
import '../../core/preferences/routine_category_collapse_store.dart';
import '../controllers/event_controller.dart';
import '../widgets/category_color_picker.dart';
import '../widgets/category_edit_dialog.dart';
import '../theme/operational_theme.dart';
import '../theme/home_pilot_theme.dart';
import '../theme/planning_theme.dart';
import '../widgets/execution_row_shell.dart';

class RoutinePage extends StatefulWidget {
  const RoutinePage({
    required this.controller,
    required this.collapseStore,
    super.key,
  });
  final EventController controller;
  final RoutineCategoryCollapseStore collapseStore;
  @override
  State<RoutinePage> createState() => _RoutinePageState();
}

class _RoutinePageState extends State<RoutinePage> {
  Set<String> collapsed = {};
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final v = await widget.collapseStore.loadCollapsedSectionKeys();
    if (mounted) setState(() => collapsed = v);
  }

  Future<void> _toggle(String? id) async {
    final key = RoutineCategoryCollapseStore.sectionKey(id);
    final value = !collapsed.contains(key);
    setState(() => value ? collapsed.add(key) : collapsed.remove(key));
    await widget.collapseStore.setCollapsed(key, value);
  }

  @override
  Widget build(BuildContext context) => OperationalVisualScope(
    builder: (context) => ColoredBox(
      color: HomePilot.canvas,
      child: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final active = widget.controller.routines
              .where((r) => r.isActive)
              .toList();
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: ListView(
                padding: OperationalTheme.pagePadding(context),
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '日常',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton.icon(
                            key: const ValueKey('create-routine-category'),
                            onPressed: () => _editCategory(context),
                            icon: const Icon(Icons.create_new_folder_outlined),
                            label: const Text('新建分类'),
                          ),
                          FilledButton.icon(
                            key: const ValueKey('create-routine'),
                            onPressed: () => _editRoutine(context),
                            icon: const Icon(Icons.add),
                            label: const Text('新建日常'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  for (
                    var i = 0;
                    i < widget.controller.routineCategories.length;
                    i++
                  )
                    _section(
                      context,
                      widget.controller.routineCategories[i],
                      i,
                      active
                          .where(
                            (r) =>
                                r.routineCategoryId ==
                                widget.controller.routineCategories[i].id,
                          )
                          .toList(),
                    ),
                  if (active.any((r) => r.routineCategoryId == null))
                    _section(
                      context,
                      null,
                      -1,
                      active.where((r) => r.routineCategoryId == null).toList(),
                    ),
                  if (widget.controller.routines.any((r) => !r.isActive)) ...[
                    const SizedBox(height: 8),
                    ExpansionTile(
                      tilePadding: const EdgeInsets.symmetric(horizontal: 4),
                      childrenPadding: const EdgeInsets.only(left: 24),
                      title: Row(
                        children: [
                          Text(
                            '已停用',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${widget.controller.routines.where((r) => !r.isActive).length}',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                      children: [
                        for (final r in widget.controller.routines.where(
                          (r) => !r.isActive,
                        ))
                          ExecutionRowShell(
                            density: JaxListDensity.compact,
                            title: r.name,
                            state: ExecutionVisualState.idle,
                            metadata: Text(_label(r)),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    widget.controller.setRoutineActive(r, true),
                                child: const Text('重新启用'),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    ),
  );

  Widget _section(
    BuildContext context,
    RoutineCategory? category,
    int categoryIndex,
    List<Routine> items,
  ) {
    final isCollapsed = collapsed.contains(
      RoutineCategoryCollapseStore.sectionKey(category?.id),
    );
    return Padding(
      key: ValueKey('routine-category-${category?.id ?? 'unclassified'}'),
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                key: ValueKey(
                  'routine-category-toggle-${category?.id ?? 'unclassified'}',
                ),
                tooltip: isCollapsed ? '展开分类' : '折叠分类',
                onPressed: () => _toggle(category?.id),
                icon: Icon(
                  isCollapsed ? Icons.chevron_right : Icons.expand_more,
                ),
              ),
              CategoryColorDot(colorKey: category?.colorKey),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  category?.name ?? '未分类',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              if (category != null)
                PopupMenuButton<String>(
                  key: ValueKey('routine-category-more-${category.id}'),
                  tooltip: '分类操作',
                  icon: const Icon(Icons.more_vert, size: 18),
                  style: HomePilot.buttonStyle().copyWith(
                    padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                  ),
                  onSelected: (v) {
                    if (v == 'rename') _editCategory(context, category);
                    if (v == 'delete') _deleteCategory(context, category);
                    if (v == 'up') {
                      widget.controller.reorderRoutineCategory(
                        category.id,
                        categoryIndex - 1,
                      );
                    }
                    if (v == 'down') {
                      widget.controller.reorderRoutineCategory(
                        category.id,
                        categoryIndex + 1,
                      );
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'rename', child: Text('重命名')),
                    if (categoryIndex > 0)
                      PopupMenuItem(
                        key: ValueKey('routine-category-up-${category.id}'),
                        value: 'up',
                        child: const Text('上移'),
                      ),
                    if (categoryIndex <
                        widget.controller.routineCategories.length - 1)
                      PopupMenuItem(
                        key: ValueKey('routine-category-down-${category.id}'),
                        value: 'down',
                        child: const Text('下移'),
                      ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text(
                        '删除分类',
                        style: TextStyle(color: PlanningTheme.error),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          if (!isCollapsed)
            for (var i = 0; i < items.length; i++)
              _routineRow(context, items[i], i, items.length),
        ],
      ),
    );
  }

  Future<void> _completePaused(RoutineExecution e) async {
    final error = await widget.controller.completeRoutineExecution(e);
    if (error != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Widget _routineRow(
    BuildContext context,
    Routine routine,
    int index,
    int count,
  ) {
    final execution = widget.controller.executionFor(routine);
    final window = routine.timeRecommendation;
    return ExecutionRowShell(
      density: JaxListDensity.compact,
      key: ValueKey('routine-${routine.id}'),
      title: routine.name,
      state: switch (execution?.status) {
        RoutineExecutionStatus.running => ExecutionVisualState.running,
        RoutineExecutionStatus.paused => ExecutionVisualState.paused,
        RoutineExecutionStatus.waiting => ExecutionVisualState.waiting,
        RoutineExecutionStatus.completed => ExecutionVisualState.completed,
        null => ExecutionVisualState.idle,
      },
      metadata: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _recurrenceLabel(routine),
            key: ValueKey('routine-recurrence-${routine.id}'),
          ),
          if (routine.isScheduled && window != null) ...[
            const SizedBox(height: 4),
            Text(
              '开始推荐 ${routineClockLabel(window.startMinute)} · 理想完成前 ${routineClockLabel(window.endMinute, relativeTo: window.startMinute)} · 最晚完成前 ${routineClockLabel(window.latestEndMinute, relativeTo: window.startMinute)}',
            ),
          ],
        ],
      ),
      time: execution?.status == RoutineExecutionStatus.running
          ? ExecutionTimeLabel(
              executionDurationLabel(widget.controller.routineElapsed(routine)),
              caption: '主动用时',
            )
          : null,
      actions: [
        if (!routine.isScheduled && routine.isActive)
          _OnDemandAction(controller: widget.controller, routine: routine),
      ],
      trailing: PopupMenuButton<String>(
        key: ValueKey('routine-more-${routine.id}'),
        tooltip: '更多操作',
        icon: const Icon(Icons.more_vert, size: 18),
        style: HomePilot.buttonStyle().copyWith(
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        ),
        onSelected: (v) async {
          if (v == 'complete-paused') {
            final e = widget.controller.executionFor(routine);
            if (e != null) _completePaused(e);
          }
          if (v == 'resume-paused') widget.controller.startRoutine(routine);
          if (v == 'edit') _editRoutine(context, routine);
          if (v == 'disable') {
            widget.controller.setRoutineActive(routine, false);
          }
          if (v == 'up' || v == 'down') {
            final error = v == 'up'
                ? await widget.controller.moveRoutineUp(routine.id)
                : await widget.controller.moveRoutineDown(routine.id);
            if (error != null && context.mounted) {
              ScaffoldMessenger.maybeOf(context)
                  ?.showSnackBar(SnackBar(content: Text(error)));
            }
          }
        },
        itemBuilder: (_) => [
          if (execution?.status == RoutineExecutionStatus.paused) ...[
            if (execution!.status.canResume)
              const PopupMenuItem(value: 'resume-paused', child: Text('继续')),
            if (execution.status.canComplete)
              const PopupMenuItem(value: 'complete-paused', child: Text('完成')),
          ],
          const PopupMenuItem(value: 'edit', child: Text('编辑')),
          if (index > 0)
            PopupMenuItem(
              key: ValueKey('routine-up-${routine.id}'),
              value: 'up',
              child: const Text('上移'),
            ),
          if (index < count - 1)
            PopupMenuItem(
              key: ValueKey('routine-down-${routine.id}'),
              value: 'down',
              child: const Text('下移'),
            ),
          const PopupMenuItem(value: 'disable', child: Text('停用')),
        ],
      ),
    );
  }

  String _label(Routine r) {
    final e = widget.controller.executionFor(r);
    final status = switch (e?.status) {
      RoutineExecutionStatus.running => '正在执行',
      RoutineExecutionStatus.paused => '已暂停',
      RoutineExecutionStatus.waiting => '等待中',
      RoutineExecutionStatus.completed => '已完成',
      null => null,
    };
    return [_recurrenceLabel(r), ?status].join(' · ');
  }

  Future<void> _editRoutine(BuildContext c, [Routine? r]) => showDialog<void>(
    context: c,
    builder: (_) =>
        _RoutineEditDialog(controller: widget.controller, routine: r),
  );
  Future<void> _editCategory(
    BuildContext c, [
    RoutineCategory? category,
  ]) async {
    await showDialog<void>(
      context: c,
      builder: (_) => CategoryEditDialog(
        title: category == null ? '新建日常分类' : '编辑日常分类',
        initialName: category?.name ?? '',
        initialColorKey:
            category?.colorKey ?? widget.controller.recommendedCategoryColorKey,
        onSave: (name, colorKey) => category == null
            ? widget.controller.createRoutineCategory(name, colorKey: colorKey)
            : widget.controller.updateRoutineCategory(
                category,
                name,
                colorKey: colorKey,
              ),
      ),
    );
  }

  Future<void> _deleteCategory(BuildContext c, RoutineCategory category) =>
      showDialog<void>(
        context: c,
        builder: (d) => AlertDialog(
          constraints: DesktopPolish.dialog(
            d,
            DesktopDialogSize.confirmation,
          ),
          title: const Text('删除分类？'),
          content: const Text('分类中的日常会移到“未分类”，执行记录不会删除。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                await widget.controller.deleteRoutineCategory(category.id);
                if (d.mounted) Navigator.pop(d);
              },
              style: PlanningTheme.destructive,
              child: const Text('删除'),
            ),
          ],
        ),
      );
}

String _routineLabel(RoutineRecurrence r) => switch (r) {
  RoutineRecurrence.daily => '每日',
  RoutineRecurrence.weekdays => '工作日',
  RoutineRecurrence.weekends => '周末',
  RoutineRecurrence.selectedWeekdays => '指定星期',
};

String _recurrenceLabel(Routine routine) {
  if (!routine.isScheduled) return '按需';
  if (routine.recurrence != RoutineRecurrence.selectedWeekdays) {
    return _routineLabel(routine.recurrence);
  }
  const names = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  final selected = [
    for (var i = 0; i < names.length; i++)
      if (routine.weekdayMask & (1 << i) != 0) names[i],
  ];
  return selected.isEmpty ? '指定星期' : selected.join(' · ');
}

class _RoutineEditDialog extends StatefulWidget {
  const _RoutineEditDialog({required this.controller, this.routine});
  final EventController controller;
  final Routine? routine;
  @override
  State<_RoutineEditDialog> createState() => _RoutineEditDialogState();
}

class _RoutineEditDialogState extends State<_RoutineEditDialog> {
  late final TextEditingController name, recommendationReason;
  late RoutineRecurrence recurrence;
  late RoutineType type;
  late int mask, recommendationStart, recommendationEnd, recommendationLatest;
  late bool timeRecommendationEnabled;
  late bool showInHomeQuickActions;
  String? category, error;
  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.routine?.name);
    recommendationReason = TextEditingController(
      text: widget.routine?.timeRecommendation?.reason,
    );
    recurrence = widget.routine?.recurrence ?? RoutineRecurrence.daily;
    type = widget.routine?.type ?? RoutineType.scheduled;
    showInHomeQuickActions = widget.routine?.showInHomeQuickActions ?? false;
    mask = widget.routine?.weekdayMask ?? 0;
    category = widget.routine?.routineCategoryId;
    timeRecommendationEnabled = widget.routine?.timeRecommendation != null;
    recommendationStart =
        widget.routine?.timeRecommendation?.startMinute ?? 11 * 60;
    recommendationEnd =
        widget.routine?.timeRecommendation?.endMinute ?? 13 * 60;
    recommendationLatest =
        widget.routine?.timeRecommendation?.latestEndMinute ?? 17 * 60;
  }

  @override
  void dispose() {
    name.dispose();
    recommendationReason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => AlertDialog(
    constraints: DesktopPolish.dialog(context, DesktopDialogSize.complex),
    title: Text(widget.routine == null ? '新建日常' : '编辑日常'),
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _EditSectionTitle('基本信息'),
            TextField(
              controller: name,
              minLines: 1,
              maxLines: null,
              style: Theme.of(c).textTheme.titleMedium,
              decoration: const InputDecoration(labelText: '名称'),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String?>(
              initialValue: category,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '分类'),
              items: [
                const DropdownMenuItem(value: null, child: Text('未分类')),
                ...widget.controller.routineCategories.map(
                  (x) => DropdownMenuItem(
                    value: x.id,
                    child: Text(x.name, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
              onChanged: (v) => setState(() => category = v),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<RoutineType>(
              isExpanded: true,
              initialValue: type,
              decoration: const InputDecoration(labelText: '类型'),
              items: const [
                DropdownMenuItem(
                  value: RoutineType.scheduled,
                  child: Text('计划型'),
                ),
                DropdownMenuItem(
                  value: RoutineType.onDemand,
                  child: Text('按需型'),
                ),
              ],
              onChanged: (value) => setState(() {
                if (type != value) showInHomeQuickActions = false;
                type = value!;
              }),
            ),
            if (type == RoutineType.scheduled) ...[
              const SizedBox(height: 24),
              _EditSectionTitle('重复规则'),
              DropdownButtonFormField<RoutineRecurrence>(
                isExpanded: true,
                initialValue: recurrence,
                decoration: const InputDecoration(labelText: '重复'),
                items: RoutineRecurrence.values
                    .map(
                      (v) => DropdownMenuItem(
                        value: v,
                        child: Text(_routineLabel(v)),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => recurrence = v!),
              ),
            ],
            if (type == RoutineType.scheduled &&
                recurrence == RoutineRecurrence.selectedWeekdays)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < 7; i++)
                    FilterChip(
                      label: Text('一二三四五六日'[i]),
                      selected: mask & (1 << i) != 0,
                      onSelected: (yes) => setState(
                        () => yes ? mask |= 1 << i : mask &= ~(1 << i),
                      ),
                    ),
                ],
              ),
            if (type == RoutineType.scheduled) ...[
              const SizedBox(height: 24),
              _EditSectionTitle('时间推荐'),
              SwitchListTile(
                key: const ValueKey('routine-time-recommendation-toggle'),
                contentPadding: EdgeInsets.zero,
                title: const Text('按时间推荐'),
                value: timeRecommendationEnabled,
                onChanged: (value) =>
                    setState(() => timeRecommendationEnabled = value),
              ),
              if (timeRecommendationEnabled) ...[
                Text(
                  '用于决定何时推荐，以及何时停止推荐该日常。',
                  style: Theme.of(c).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                for (final field in [
                  ('开始推荐', 'routine-time-start', recommendationStart, 0),
                  ('理想完成前', 'routine-time-end', recommendationEnd, 1),
                  ('最晚完成前', 'routine-time-latest', recommendationLatest, 2),
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(child: Text(field.$1)),
                        Flexible(
                          child: TextButton(
                            key: ValueKey(field.$2),
                            onPressed: () => _pickTime(field: field.$4),
                            child: Text(
                              routineClockLabel(
                                field.$3,
                                relativeTo: field.$4 == 0
                                    ? null
                                    : recommendationStart,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                TextField(
                  key: const ValueKey('routine-time-reason'),
                  controller: recommendationReason,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: '推荐理由（可选）'),
                ),
              ],
            ],
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(c).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
      FilledButton(
        onPressed: _save,
        child: Text(widget.routine == null ? '创建' : '保存'),
      ),
    ],
  );
  Future<void> _save() async {
    final r = widget.routine;
    final cleanReason = recommendationReason.text.trim();
    final timeRecommendation =
        type == RoutineType.scheduled && timeRecommendationEnabled
        ? RoutineTimeRecommendation(
            startMinute: recommendationStart,
            endMinute: recommendationEnd,
            latestEndMinute: recommendationLatest,
            reason: cleanReason.isEmpty ? null : cleanReason,
          )
        : null;
    final result = r == null
        ? await widget.controller.createRoutine(
            name.text,
            category,
            recurrence,
            mask,
            type: type,
            timeRecommendation: timeRecommendation,
            showInHomeQuickActions: showInHomeQuickActions,
          )
        : await widget.controller.updateRoutine(
            r,
            name.text,
            category,
            recurrence,
            mask,
            type: type,
            timeRecommendation: timeRecommendation,
            updateTimeRecommendation: true,
            showInHomeQuickActions: showInHomeQuickActions,
          );
    if (!mounted) return;
    if (result == null) {
      Navigator.pop(context);
    } else {
      setState(() => error = result);
    }
  }

  Future<void> _pickTime({required int field}) async {
    final minute = [
      recommendationStart,
      recommendationEnd,
      recommendationLatest,
    ][field];
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minute ~/ 60, minute: minute % 60),
    );
    if (picked == null || !mounted) return;
    setState(() {
      final value = picked.hour * 60 + picked.minute;
      if (field == 0) {
        recommendationStart = value;
      } else if (field == 1) {
        recommendationEnd = value;
      } else {
        recommendationLatest = value;
      }
    });
  }
}

class _OnDemandAction extends StatelessWidget {
  const _OnDemandAction({required this.controller, required this.routine});
  final EventController controller;
  final Routine routine;

  @override
  Widget build(BuildContext context) {
    final execution = controller.executionFor(routine);
    if (execution?.status == RoutineExecutionStatus.running) {
      return const SizedBox.shrink();
    }
    final waiting = execution?.status == RoutineExecutionStatus.waiting;
    final paused =
        waiting || execution?.status == RoutineExecutionStatus.paused;
    return OutlinedButton.icon(
      style: HomePilot.buttonStyle(outlined: true),
      key: ValueKey('routine-on-demand-start-${routine.id}'),
      onPressed: () async {
        final error = await controller.startRoutine(routine);
        if (error != null && context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(error)));
        }
      },
      icon: Icon(paused ? Icons.play_arrow : Icons.add, size: 18),
      label: Text(
        waiting
            ? '继续'
            : paused
            ? '继续'
            : '开始',
      ),
    );
  }
}

class _EditSectionTitle extends StatelessWidget {
  const _EditSectionTitle(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(title, style: Theme.of(context).textTheme.titleLarge),
  );
}
