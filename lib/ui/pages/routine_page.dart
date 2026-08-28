import 'package:flutter/material.dart';

import '../../core/entities/routine.dart';
import '../../core/entities/routine_category.dart';
import '../../core/preferences/routine_category_collapse_store.dart';
import '../controllers/event_controller.dart';
import '../widgets/category_color_picker.dart';
import '../widgets/category_edit_dialog.dart';
import '../widgets/routine_reorder_buttons.dart';

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
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 72),
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('日常', style: Theme.of(context).textTheme.headlineMedium),
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
                        style: Theme.of(context).textTheme.titleSmall,
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
                      ListTile(
                        dense: true,
                        title: Text(r.name, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          _label(r),
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: TextButton(
                          onPressed: () =>
                              widget.controller.setRoutineActive(r, true),
                          child: const Text('重新启用'),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
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
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(
            children: [
              IconButton(
                key: ValueKey(
                  'routine-category-toggle-${category?.id ?? 'unclassified'}',
                ),
                visualDensity: VisualDensity.compact,
                onPressed: () => _toggle(category?.id),
                icon: Icon(
                  isCollapsed ? Icons.chevron_right : Icons.expand_more,
                ),
              ),
              CategoryColorDot(colorKey: category?.colorKey),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        category?.name ?? '未分类',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${items.length} 项',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (category != null) ...[
                if (categoryIndex > 0)
                  IconButton(
                    key: ValueKey('routine-category-up-${category.id}'),
                    tooltip: '上移',
                    onPressed: () => widget.controller.reorderRoutineCategory(
                      category.id,
                      categoryIndex - 1,
                    ),
                    icon: const Icon(Icons.arrow_upward),
                    visualDensity: VisualDensity.compact,
                  ),
                if (categoryIndex <
                    widget.controller.routineCategories.length - 1)
                  IconButton(
                    key: ValueKey('routine-category-down-${category.id}'),
                    tooltip: '下移',
                    onPressed: () => widget.controller.reorderRoutineCategory(
                      category.id,
                      categoryIndex + 1,
                    ),
                    icon: const Icon(Icons.arrow_downward),
                    visualDensity: VisualDensity.compact,
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
            ],
          ),
        ),
        const Divider(height: 1),
        if (!isCollapsed)
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  _routineRow(context, items[i], i, items.length),
                  if (i < items.length - 1) const Divider(height: 1),
                ],
              ],
            ),
          ),
        const SizedBox(height: 6),
      ],
    );
  }

  Widget _routineRow(
    BuildContext context,
    Routine routine,
    int index,
    int count,
  ) => LayoutBuilder(
    builder: (context, constraints) {
      final controls = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          RoutineReorderButtons(
            controller: widget.controller,
            routineId: routine.id,
            index: index,
            count: count,
          ),
          PopupMenuButton<String>(
            key: ValueKey('routine-more-${routine.id}'),
            onSelected: (v) {
              if (v == 'edit') _editRoutine(context, routine);
              if (v == 'disable') {
                widget.controller.setRoutineActive(routine, false);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('编辑')),
              PopupMenuItem(value: 'disable', child: Text('停用')),
            ],
          ),
        ],
      );
      final recurrence = Text(
        _label(routine),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
      return Padding(
        key: ValueKey('routine-${routine.id}'),
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: constraints.maxWidth >= 540
            ? Row(
                children: [
                  Expanded(
                    child: Text(
                      routine.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(width: 180, child: recurrence),
                  const SizedBox(width: 4),
                  controls,
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          routine.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      controls,
                    ],
                  ),
                  recurrence,
                ],
              ),
      );
    },
  );

  String _label(Routine r) {
    final e = widget.controller.executionFor(r);
    final status = switch (e?.status) {
      RoutineExecutionStatus.running => '正在执行',
      RoutineExecutionStatus.paused => '已暂停',
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
  RoutineRecurrence.daily => '每日',
  RoutineRecurrence.weekdays => '工作日',
  RoutineRecurrence.weekends => '周末',
  RoutineRecurrence.selectedWeekdays => '指定星期',
};

String _recurrenceLabel(Routine routine) {
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
