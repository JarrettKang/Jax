import 'package:flutter/material.dart';

import '../../core/entities/routine.dart';
import '../controllers/event_controller.dart';
import '../widgets/category_selector.dart';

class RoutinePage extends StatelessWidget {
  const RoutinePage({required this.controller, super.key});
  final EventController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('日常', style: Theme.of(context).textTheme.headlineSmall),
              FilledButton.icon(
                key: const ValueKey('create-routine'),
                onPressed: () => _edit(context),
                icon: const Icon(Icons.add),
                label: const Text('新建日常'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (final r in controller.routines.where((r) => r.isActive))
            ListTile(
              title: Text(r.name),
              subtitle: Text(_managementLabel(r)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (controller.routines.indexOf(r) > 0)
                    IconButton(
                      key: ValueKey('routine-up-${r.id}'),
                      tooltip: '上移',
                      onPressed: () => controller.reorderRoutine(
                        r.id,
                        controller.routines.indexOf(r) - 1,
                      ),
                      icon: const Icon(Icons.arrow_upward),
                    ),
                  if (controller.routines.indexOf(r) <
                      controller.routines.length - 1)
                    IconButton(
                      key: ValueKey('routine-down-${r.id}'),
                      tooltip: '下移',
                      onPressed: () => controller.reorderRoutine(
                        r.id,
                        controller.routines.indexOf(r) + 1,
                      ),
                      icon: const Icon(Icons.arrow_downward),
                    ),
                  PopupMenuButton<String>(
                    key: ValueKey('routine-more-${r.id}'),
                    onSelected: (v) {
                      if (v == 'edit') _edit(context, r);
                      if (v == 'disable') controller.setRoutineActive(r, false);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('编辑')),
                      PopupMenuItem(value: 'disable', child: Text('停用')),
                    ],
                  ),
                ],
              ),
            ),
          if (controller.routines.any((r) => !r.isActive))
            ExpansionTile(
              title: const Text('已停用'),
              children: [
                for (final r in controller.routines.where((r) => !r.isActive))
                  ListTile(
                    title: Text(r.name),
                    trailing: TextButton(
                      onPressed: () => controller.setRoutineActive(r, true),
                      child: const Text('重新启用'),
                    ),
                  ),
              ],
            ),
        ],
      );
    },
  );
  String _managementLabel(Routine r) {
    final category =
        controller.categories
            .where((c) => c.id == r.categoryId)
            .firstOrNull
            ?.name ??
        '未分类';
    final execution = controller.executionFor(r);
    final status = switch (execution?.status) {
      RoutineExecutionStatus.running => '正在执行',
      RoutineExecutionStatus.paused => '已暂停',
      RoutineExecutionStatus.completed => '已完成',
      null => null,
    };
    return [_label(r.recurrence), category, ?status].join(' · ');
  }

  String _label(RoutineRecurrence r) => _routineLabel(r);
  Future<void> _edit(BuildContext context, [Routine? routine]) =>
      showDialog<void>(
        context: context,
        builder: (_) =>
            _RoutineEditDialog(controller: controller, routine: routine),
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
  late final TextEditingController _name;
  late RoutineRecurrence _recurrence;
  late int _mask;
  String? _category;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.routine?.name);
    _recurrence = widget.routine?.recurrence ?? RoutineRecurrence.daily;
    _mask = widget.routine?.weekdayMask ?? 0;
    _category = widget.routine?.categoryId;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.routine == null ? '新建日常' : '编辑日常'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: '名称'),
            ),
            CategorySelector(
              categories: widget.controller.categories,
              value: _category,
              onChanged: (value) => setState(() => _category = value),
            ),
            DropdownButtonFormField<RoutineRecurrence>(
              initialValue: _recurrence,
              decoration: const InputDecoration(labelText: '重复'),
              items: RoutineRecurrence.values
                  .map(
                    (v) => DropdownMenuItem(
                      value: v,
                      child: Text(_routineLabel(v)),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _recurrence = v!),
            ),
            if (_recurrence == RoutineRecurrence.selectedWeekdays)
              Wrap(
                children: [
                  for (var i = 0; i < 7; i++)
                    FilterChip(
                      label: Text('一二三四五六日'[i]),
                      selected: _mask & (1 << i) != 0,
                      onSelected: (yes) => setState(() {
                        if (yes) {
                          _mask |= 1 << i;
                        } else {
                          _mask &= ~(1 << i);
                        }
                      }),
                    ),
                ],
              ),
            if (_errorText != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _errorText!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _save, child: const Text('保存')),
    ],
  );

  Future<void> _save() async {
    final routine = widget.routine;
    final error = routine == null
        ? await widget.controller.createRoutine(
            _name.text,
            _category,
            _recurrence,
            _mask,
          )
        : await widget.controller.updateRoutine(
            routine,
            _name.text,
            _category,
            _recurrence,
            _mask,
          );
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context);
    } else {
      setState(() => _errorText = error);
    }
  }
}
