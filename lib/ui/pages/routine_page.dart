import 'package:flutter/material.dart';

import '../../core/entities/routine.dart';
import '../../core/entities/routine_category.dart';
import '../../core/preferences/routine_category_collapse_store.dart';
import '../controllers/event_controller.dart';
import '../widgets/routine_reorder_buttons.dart';
import '../widgets/execution_time_editor.dart';
import '../../core/entities/execution_time_segment.dart';

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
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final active = widget.controller.routines
          .where((r) => r.isActive)
          .toList();
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('日常', style: Theme.of(context).textTheme.headlineSmall),
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
          for (var i = 0; i < widget.controller.routineCategories.length; i++)
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
          if (widget.controller.routines.any((r) => !r.isActive))
            ExpansionTile(
              title: const Text('已停用'),
              children: [
                for (final r in widget.controller.routines.where(
                  (r) => !r.isActive,
                ))
                  ListTile(
                    title: Text(r.name),
                    subtitle: Text(_label(r)),
                    trailing: TextButton(
                      onPressed: () =>
                          widget.controller.setRoutineActive(r, true),
                      child: const Text('重新启用'),
                    ),
                  ),
              ],
            ),
        ],
      );
    },
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
    return Column(
      key: ValueKey('routine-category-${category?.id ?? 'unclassified'}'),
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: IconButton(
            key: ValueKey(
              'routine-category-toggle-${category?.id ?? 'unclassified'}',
            ),
            onPressed: () => _toggle(category?.id),
            icon: Icon(isCollapsed ? Icons.chevron_right : Icons.expand_more),
          ),
          title: Text(
            category?.name ?? '未分类',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          trailing: category == null
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (categoryIndex > 0)
                      IconButton(
                        key: ValueKey('routine-category-up-${category.id}'),
                        tooltip: '上移',
                        onPressed: () =>
                            widget.controller.reorderRoutineCategory(
                              category.id,
                              categoryIndex - 1,
                            ),
                        icon: const Icon(Icons.arrow_upward),
                      ),
                    if (categoryIndex <
                        widget.controller.routineCategories.length - 1)
                      IconButton(
                        key: ValueKey('routine-category-down-${category.id}'),
                        tooltip: '下移',
                        onPressed: () =>
                            widget.controller.reorderRoutineCategory(
                              category.id,
                              categoryIndex + 1,
                            ),
                        icon: const Icon(Icons.arrow_downward),
                      ),
                    PopupMenuButton<String>(
                      key: ValueKey('routine-category-more-${category.id}'),
                      onSelected: (v) {
                        if (v == 'rename') _editCategory(context, category);
                        if (v == 'delete') _deleteCategory(context, category);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'rename', child: Text('重命名')),
                        PopupMenuItem(value: 'delete', child: Text('删除分类')),
                      ],
                    ),
                  ],
                ),
        ),
        if (!isCollapsed)
          for (var i = 0; i < items.length; i++)
            ListTile(
              key: ValueKey('routine-${items[i].id}'),
              title: Text(items[i].name),
              subtitle: Text(_label(items[i])),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RoutineReorderButtons(
                    controller: widget.controller,
                    routineId: items[i].id,
                    index: i,
                    count: items.length,
                  ),
                  PopupMenuButton<String>(
                    key: ValueKey('routine-more-${items[i].id}'),
                    onSelected: (v) {
                      if (v == 'edit') _editRoutine(context, items[i]);
                      if (v == 'disable') {
                        widget.controller.setRoutineActive(items[i], false);
                      }
                      if (v == 'time') _editTimes(context, items[i]);
                      if (v == 'adjustPause') {
                        _adjust(context, items[i], false);
                      }
                      if (v == 'adjustComplete') {
                        _adjust(context, items[i], true);
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'edit', child: Text('编辑')),
                      const PopupMenuItem(value: 'disable', child: Text('停用')),
                      if (widget.controller.executionFor(items[i])?.status
                          case RoutineExecutionStatus.paused ||
                              RoutineExecutionStatus.completed)
                        const PopupMenuItem(
                          value: 'time',
                          child: Text('编辑执行时间'),
                        ),
                      if (widget.controller.executionFor(items[i])?.status ==
                          RoutineExecutionStatus.running) ...[
                        const PopupMenuItem(
                          value: 'adjustPause',
                          child: Text('调整结束并暂停'),
                        ),
                        const PopupMenuItem(
                          value: 'adjustComplete',
                          child: Text('调整结束并完成'),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
        const Divider(height: 1),
      ],
    );
  }

  String _label(Routine r) {
    final e = widget.controller.executionFor(r);
    final status = switch (e?.status) {
      RoutineExecutionStatus.running => '正在执行',
      RoutineExecutionStatus.paused => '已暂停',
      RoutineExecutionStatus.completed => '已完成',
      null => null,
    };
    return [_routineLabel(r.recurrence), ?status].join(' · ');
  }

  Future<void> _editTimes(BuildContext c, Routine r) async {
    final execution = widget.controller.executionFor(r);
    if (execution == null) {
      ScaffoldMessenger.of(c)
          .showSnackBar(const SnackBar(content: Text('该日常今天还没有执行记录')));
      return;
    }
    if (execution.status == RoutineExecutionStatus.running) {
      return;
    }
    await showExecutionTimeEditor(
      c,
      controller: widget.controller,
      ownerType: ExecutionOwnerType.routine,
      ownerId: execution.id,
      ownerName: r.name,
      contextLabel: 'Routine',
    );
  }

  Future<void> _adjust(BuildContext c, Routine r, bool complete) async {
    final execution = widget.controller.executionFor(r);
    if (execution?.status != RoutineExecutionStatus.running) return;
    final items = await widget.controller.executionSegments(
      ExecutionOwnerType.routine,
      execution!.id,
    );
    final open = items.where((s) => s.endedAt == null).firstOrNull;
    if (open != null && c.mounted) {
      await showFinishRunningAtDialog(
        c,
        controller: widget.controller,
        segment: open,
        complete: complete,
      );
    }
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
    final input = TextEditingController(text: category?.name);
    await showDialog<void>(
      context: c,
      builder: (d) => AlertDialog(
        title: Text(category == null ? '新建日常分类' : '重命名日常分类'),
        content: TextField(
          key: const ValueKey('routine-category-name'),
          controller: input,
          autofocus: true,
          decoration: const InputDecoration(labelText: '名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final error = category == null
                  ? await widget.controller.createRoutineCategory(input.text)
                  : await widget.controller.renameRoutineCategory(
                      category,
                      input.text,
                    );
              if (error == null && d.mounted) Navigator.pop(d);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteCategory(BuildContext c, RoutineCategory category) =>
      showDialog<void>(
        context: c,
        builder: (d) => AlertDialog(
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
              child: const Text('删除'),
            ),
          ],
        ),
      );
}

String _routineLabel(RoutineRecurrence r) => switch (r) {
  RoutineRecurrence.daily => '每天',
  RoutineRecurrence.weekdays => '工作日',
  RoutineRecurrence.weekends => '周末',
  RoutineRecurrence.selectedWeekdays => '指定星期',
};

class _RoutineEditDialog extends StatefulWidget {
  const _RoutineEditDialog({required this.controller, this.routine});
  final EventController controller;
  final Routine? routine;
  @override
  State<_RoutineEditDialog> createState() => _RoutineEditDialogState();
}

class _RoutineEditDialogState extends State<_RoutineEditDialog> {
  late final TextEditingController name;
  late RoutineRecurrence recurrence;
  late int mask;
  String? category, error;
  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.routine?.name);
    recurrence = widget.routine?.recurrence ?? RoutineRecurrence.daily;
    mask = widget.routine?.weekdayMask ?? 0;
    category = widget.routine?.routineCategoryId;
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => AlertDialog(
    title: Text(widget.routine == null ? '新建日常' : '编辑日常'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: '名称'),
            ),
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
            DropdownButtonFormField<RoutineRecurrence>(
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
            if (recurrence == RoutineRecurrence.selectedWeekdays)
              Wrap(
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
    final result = r == null
        ? await widget.controller.createRoutine(
            name.text,
            category,
            recurrence,
            mask,
          )
        : await widget.controller.updateRoutine(
            r,
            name.text,
            category,
            recurrence,
            mask,
          );
    if (!mounted) return;
    if (result == null) {
      Navigator.pop(context);
    } else {
      setState(() => error = result);
    }
  }
}
