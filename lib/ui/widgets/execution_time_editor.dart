import 'package:flutter/material.dart';

import '../../core/entities/execution_time_segment.dart';
import '../controllers/event_controller.dart';

Future<void> showExecutionTimeEditor(
  BuildContext context, {
  required EventController controller,
  required ExecutionOwnerType ownerType,
  required String ownerId,
  required String ownerName,
  String? contextLabel,
}) => showDialog<void>(
  context: context,
  builder: (_) => _ExecutionTimeEditor(
    controller: controller,
    ownerType: ownerType,
    ownerId: ownerId,
    ownerName: ownerName,
    contextLabel: contextLabel,
  ),
);

Future<void> showExecutionTimeOwnerPicker(
  BuildContext rootContext, {
  required EventController controller,
}) => showDialog<void>(
  context: rootContext,
  builder: (pickerContext) => AlertDialog(
    title: const Text('执行时间纠错'),
    content: SizedBox(
      width: 520,
      child: FutureBuilder<List<ExecutionTimeOwner>>(
        future: controller.executionTimeOwners(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.requireData.isEmpty) return const Text('暂无可编辑的执行记录');
          return ListView(
            shrinkWrap: true,
            children: [
              for (final owner in snapshot.requireData)
                ListTile(
                  key: ValueKey(
                    'execution-owner-${owner.type.name}-${owner.id}',
                  ),
                  title: Text(
                    owner.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${owner.type == ExecutionOwnerType.event ? 'Event' : 'Routine'} · ${owner.detail ?? owner.status}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(pickerContext);
                    showExecutionTimeEditor(
                      rootContext,
                      controller: controller,
                      ownerType: owner.type,
                      ownerId: owner.id,
                      ownerName: owner.name,
                      contextLabel: owner.type == ExecutionOwnerType.event
                          ? 'Event'
                          : 'Routine · ${owner.detail}',
                    );
                  },
                ),
            ],
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(pickerContext),
        child: const Text('关闭'),
      ),
    ],
  ),
);

Future<void> showFinishRunningAtDialog(
  BuildContext context, {
  required EventController controller,
  required ExecutionTimeSegment segment,
  required bool complete,
}) async {
  final end = await showDialog<DateTime>(
    context: context,
    builder: (_) => _DateTimeRangeDialog(
      title: complete ? '指定完成时间' : '指定暂停时间',
      fixedStart: segment.startedAt.toLocal(),
    ),
  );
  if (end == null || !context.mounted) return;
  final error = await controller.finishRunningAt(
    segment,
    end,
    complete: complete,
  );
  if (error != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }
}

class _ExecutionTimeEditor extends StatefulWidget {
  const _ExecutionTimeEditor({
    required this.controller,
    required this.ownerType,
    required this.ownerId,
    required this.ownerName,
    this.contextLabel,
  });
  final EventController controller;
  final ExecutionOwnerType ownerType;
  final String ownerId, ownerName;
  final String? contextLabel;
  @override
  State<_ExecutionTimeEditor> createState() => _ExecutionTimeEditorState();
}

class _ExecutionTimeEditorState extends State<_ExecutionTimeEditor> {
  late Future<List<ExecutionTimeSegment>> data = _load();
  Future<List<ExecutionTimeSegment>> _load() =>
      widget.controller.executionSegments(widget.ownerType, widget.ownerId);
  void refresh() => setState(() => data = _load());
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('编辑执行时间'),
    content: SizedBox(
      width: 560,
      child: FutureBuilder<List<ExecutionTimeSegment>>(
        future: data,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final closed = snapshot.requireData
              .where((s) => s.endedAt != null)
              .toList();
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.ownerName,
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (widget.contextLabel != null)
                  Text(
                    widget.contextLabel!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                const SizedBox(height: 16),
                Text('执行记录', style: Theme.of(context).textTheme.titleSmall),
                if (closed.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('暂无执行时间记录'),
                  ),
                for (final s in closed)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${_format(s.startedAt)} – ${_format(s.endedAt!)}',
                    ),
                    subtitle: Text(
                      '${s.endedAt!.difference(s.startedAt).inMinutes} 分钟',
                    ),
                    trailing: Wrap(
                      children: [
                        IconButton(
                          key: ValueKey('segment-edit-${s.id}'),
                          tooltip: '编辑',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _edit(context, s),
                        ),
                        IconButton(
                          key: ValueKey('segment-delete-${s.id}'),
                          tooltip: '删除',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(context, s),
                        ),
                      ],
                    ),
                  ),
                TextButton.icon(
                  key: const ValueKey('segment-add'),
                  onPressed: () => _add(context),
                  icon: const Icon(Icons.add),
                  label: const Text('添加一段'),
                ),
              ],
            ),
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
    ],
  );
  static String _format(DateTime utc) {
    final d = utc.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.month}月${d.day}日 ${two(d.hour)}:${two(d.minute)}';
  }

  Future<void> _add(BuildContext c) async {
    final range = await showDialog<(DateTime, DateTime)>(
      context: c,
      builder: (_) => const _DateTimeRangeDialog(title: '添加执行时间'),
    );
    if (range == null) return;
    final error = await widget.controller.addExecutionSegment(
      widget.ownerType,
      widget.ownerId,
      widget.ownerName,
      range.$1,
      range.$2,
    );
    if (error == null) {
      refresh();
    } else if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<void> _edit(BuildContext c, ExecutionTimeSegment s) async {
    final range = await showDialog<(DateTime, DateTime)>(
      context: c,
      builder: (_) => _DateTimeRangeDialog(
        title: '编辑执行时间',
        initialStart: s.startedAt.toLocal(),
        initialEnd: s.endedAt!.toLocal(),
      ),
    );
    if (range == null) return;
    final error = await widget.controller.editExecutionSegment(
      s,
      range.$1,
      range.$2,
    );
    if (error == null) {
      refresh();
    } else if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<void> _delete(BuildContext c, ExecutionTimeSegment s) async {
    final yes = await showDialog<bool>(
      context: c,
      builder: (d) => AlertDialog(
        title: const Text('删除这段执行记录？'),
        content: Text(
          '${_format(s.startedAt)} – ${_format(s.endedAt!)}\n${s.endedAt!.difference(s.startedAt).inMinutes} 分钟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (yes == true) {
      final error = await widget.controller.deleteExecutionSegment(s);
      if (error == null) refresh();
    }
  }
}

class _DateTimeRangeDialog extends StatefulWidget {
  const _DateTimeRangeDialog({
    required this.title,
    this.initialStart,
    this.initialEnd,
    this.fixedStart,
  });
  final String title;
  final DateTime? initialStart, initialEnd, fixedStart;
  @override
  State<_DateTimeRangeDialog> createState() => _DateTimeRangeDialogState();
}

class _DateTimeRangeDialogState extends State<_DateTimeRangeDialog> {
  late DateTime start, end;
  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    start =
        widget.fixedStart ??
        widget.initialStart ??
        now.subtract(const Duration(minutes: 30));
    end = widget.initialEnd ?? now;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.fixedStart == null) _picker('开始', start, (v) => start = v),
        _picker('结束', end, (v) => end = v),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        key: const ValueKey('segment-time-save'),
        onPressed: () => Navigator.pop(
          context,
          widget.fixedStart != null ? end : (start, end),
        ),
        child: const Text('保存'),
      ),
    ],
  );
  Widget _picker(String label, DateTime value, ValueChanged<DateTime> set) =>
      ListTile(
        title: Text(label),
        subtitle: Text(_ExecutionTimeEditorState._format(value)),
        trailing: const Icon(Icons.calendar_month),
        onTap: () async {
          final date = await showDatePicker(
            context: context,
            initialDate: value,
            firstDate: DateTime(2000),
            lastDate: DateTime.now(),
          );
          if (date == null || !mounted) return;
          final time = await showTimePicker(
            context: context,
            initialTime: TimeOfDay.fromDateTime(value),
          );
          if (time != null) {
            setState(
              () => set(
                DateTime(
                  date.year,
                  date.month,
                  date.day,
                  time.hour,
                  time.minute,
                ),
              ),
            );
          }
        },
      );
}
