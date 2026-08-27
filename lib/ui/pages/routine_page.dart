import 'package:flutter/material.dart';

import '../../core/entities/routine.dart';
import '../controllers/event_controller.dart';

class RoutinePage extends StatelessWidget {
  const RoutinePage({required this.controller, super.key});
  final EventController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final today = controller.todayRoutines;
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
          Text('今日备用执行', style: Theme.of(context).textTheme.titleLarge),
          const Text('主要执行入口已统一到“今日”。'),
          const SizedBox(height: 8),
          if (today.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('当前 Jax day 没有命中的日常'),
              ),
            ),
          for (final r in today) _card(context, r),
          const Divider(height: 40),
          Text('管理日常', style: Theme.of(context).textTheme.titleLarge),
          for (final r in controller.routines.where((r) => r.isActive))
            ListTile(
              title: Text(r.name),
              subtitle: Text(_label(r.recurrence)),
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
  Widget _card(BuildContext context, Routine r) {
    final e = controller.executionFor(r);
    final elapsed = _duration(controller.routineElapsed(r));
    final status = e == null
        ? '未开始'
        : switch (e.status) {
            RoutineExecutionStatus.running => '正在执行 · $elapsed',
            RoutineExecutionStatus.paused => '已暂停 · 已执行 $elapsed',
            RoutineExecutionStatus.completed => '完成 · $elapsed',
          };
    final actions = <Widget>[];
    if (e == null) {
      actions.add(
        _action('开始', Icons.play_arrow, () => controller.startRoutine(r)),
      );
    } else if (e.status == RoutineExecutionStatus.running) {
      actions.add(_action('暂停', Icons.pause, () => controller.pauseRoutine(r)));
      actions.add(_complete(r));
    } else if (e.status == RoutineExecutionStatus.paused) {
      actions.add(
        _action('恢复', Icons.play_arrow, () => controller.startRoutine(r)),
      );
      actions.add(_complete(r));
    }
    final category =
        controller.categories
            .where((c) => c.id == r.categoryId)
            .firstOrNull
            ?.name ??
        '未分类';
    return Card(
      key: ValueKey('routine-${r.id}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 180, maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text('$category · ${_label(r.recurrence)}'),
                  Text(status),
                ],
              ),
            ),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ),
      ),
    );
  }

  Widget _action(String text, IconData icon, VoidCallback tap) =>
      OutlinedButton.icon(onPressed: tap, icon: Icon(icon), label: Text(text));
  Widget _complete(Routine r) => FilledButton.icon(
    onPressed: () => controller.completeRoutine(r),
    icon: const Icon(Icons.check),
    label: const Text('完成'),
  );
  String _label(RoutineRecurrence r) => switch (r) {
    RoutineRecurrence.daily => '每天',
    RoutineRecurrence.weekdays => '工作日',
    RoutineRecurrence.weekends => '周末',
    RoutineRecurrence.selectedWeekdays => '指定星期',
  };
  String _duration(Duration d) =>
      '${d.inHours.toString().padLeft(2, '0')}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  Future<void> _edit(BuildContext context, [Routine? routine]) async {
    final name = TextEditingController(text: routine?.name);
    var recurrence = routine?.recurrence ?? RoutineRecurrence.daily;
    var mask = routine?.weekdayMask ?? 0;
    String? category = routine?.categoryId;
    String? errorText;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(routine == null ? '新建日常' : '编辑日常'),
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
                    decoration: const InputDecoration(labelText: '分类'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('未分类')),
                      ...controller.categories.map(
                        (c) =>
                            DropdownMenuItem(value: c.id, child: Text(c.name)),
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
                            child: Text(_label(v)),
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
                            onSelected: (yes) => setState(() {
                              if (yes) {
                                mask |= 1 << i;
                              } else {
                                mask &= ~(1 << i);
                              }
                            }),
                          ),
                      ],
                    ),
                  if (errorText != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        errorText!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                final error = routine == null
                    ? await controller.createRoutine(
                        name.text,
                        category,
                        recurrence,
                        mask,
                      )
                    : await controller.updateRoutine(
                        routine,
                        name.text,
                        category,
                        recurrence,
                        mask,
                      );
                if (error == null && dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                } else if (error != null) {
                  setState(() => errorText = error);
                }
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
  }
}
