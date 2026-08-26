import 'package:flutter/material.dart';

import '../../core/entities/event_status.dart';
import '../../core/entities/jax_event.dart';
import '../controllers/event_controller.dart';
import 'event_hierarchy_dialog.dart';

class EventsPage extends StatelessWidget {
  const EventsPage({required this.controller, super.key});
  final EventController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => Scaffold(
      body: controller.loading
          ? const Center(child: CircularProgressIndicator())
          : controller.events.isEmpty
          ? const Center(child: Text('暂无未完成事件'))
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              children: controller.events
                  .map(
                    (event) => Padding(
                      padding: EdgeInsets.only(
                        left: (controller.hierarchyDepthFor(event.id) * 24.0)
                            .clamp(0.0, 72.0),
                      ),
                      child: Card(
                        clipBehavior: Clip.antiAlias,
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant,
                                width: 2,
                              ),
                            ),
                          ),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final actions = _actions(context, event);
                              if (constraints.maxWidth < 600) {
                                return Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    12,
                                    8,
                                    8,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        event.name,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(_statusText(event)),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: Wrap(children: actions),
                                      ),
                                    ],
                                  ),
                                );
                              }
                              return ListTile(
                                title: Text(event.name),
                                subtitle: Text(_statusText(event)),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: actions,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditor(context, null),
        icon: const Icon(Icons.add),
        label: const Text('新建事件'),
      ),
    ),
  );
  String _statusText(JaxEvent event) => event.status == EventStatus.running
      ? '正在进行 · ${_duration(controller.elapsedFor(event))}'
      : event.status == EventStatus.paused
      ? '已暂停 · ${_duration(controller.elapsedFor(event))}'
      : '未开始';

  List<Widget> _actions(BuildContext context, JaxEvent event) => [
    if (event.status == EventStatus.pending)
      IconButton(
        key: ValueKey('start-${event.id}'),
        icon: const Icon(Icons.play_arrow),
        tooltip: '开始',
        onPressed: () => _run(context, () => controller.start(event.id)),
      ),
    if (event.status == EventStatus.paused)
      IconButton(
        key: ValueKey('resume-${event.id}'),
        icon: const Icon(Icons.play_arrow),
        tooltip: '恢复',
        onPressed: () => _run(context, () => controller.resume(event.id)),
      ),
    if (event.status == EventStatus.running)
      OutlinedButton.icon(
        key: ValueKey('pause-${event.id}'),
        icon: const Icon(Icons.pause),
        label: const Text('暂停'),
        onPressed: () => _run(context, () => controller.pause(event.id)),
      ),
    if (event.status == EventStatus.running) const SizedBox(width: 16),
    if (event.status == EventStatus.running)
      FilledButton.tonalIcon(
        key: ValueKey('complete-${event.id}'),
        icon: const Icon(Icons.check),
        label: const Text('完成'),
        onPressed: () => _run(context, () => controller.complete(event.id)),
      ),
    PopupMenuButton<_EventMenuAction>(
      key: ValueKey('more-${event.id}'),
      tooltip: '更多操作',
      onSelected: (action) => _selectMenuAction(context, event, action),
      itemBuilder: (context) => _menuItems(event),
    ),
  ];

  List<PopupMenuEntry<_EventMenuAction>> _menuItems(JaxEvent event) => [
    PopupMenuItem(
      key: ValueKey('hierarchy-${event.id}'),
      value: _EventMenuAction.hierarchy,
      child: const ListTile(
        leading: Icon(Icons.account_tree_outlined),
        title: Text('层级详情'),
      ),
    ),
    if (controller.siblingIndexFor(event.id) > 0)
      PopupMenuItem(
        key: ValueKey('move-up-${event.id}'),
        value: _EventMenuAction.moveUp,
        child: const ListTile(
          leading: Icon(Icons.arrow_upward),
          title: Text('上移'),
        ),
      ),
    if (controller.siblingIndexFor(event.id) >= 0 &&
        controller.siblingIndexFor(event.id) <
            controller.siblingCountFor(event.id) - 1)
      PopupMenuItem(
        key: ValueKey('move-down-${event.id}'),
        value: _EventMenuAction.moveDown,
        child: const ListTile(
          leading: Icon(Icons.arrow_downward),
          title: Text('下移'),
        ),
      ),
    if (event.status != EventStatus.running)
      PopupMenuItem(
        key: ValueKey('edit-${event.id}'),
        value: _EventMenuAction.edit,
        child: const ListTile(leading: Icon(Icons.edit), title: Text('编辑事件')),
      ),
    if (event.status != EventStatus.running &&
        !controller.hasDirectChildren(event.id))
      PopupMenuItem(
        key: ValueKey('delete-${event.id}'),
        value: _EventMenuAction.delete,
        child: const ListTile(
          leading: Icon(Icons.delete_outline),
          title: Text('删除事件'),
        ),
      ),
  ];

  void _selectMenuAction(
    BuildContext context,
    JaxEvent event,
    _EventMenuAction action,
  ) {
    switch (action) {
      case _EventMenuAction.hierarchy:
        showEventHierarchyDialog(context, controller: controller, event: event);
        return;
      case _EventMenuAction.moveUp:
        _run(context, () => controller.moveUp(event.id));
        return;
      case _EventMenuAction.moveDown:
        _run(context, () => controller.moveDown(event.id));
        return;
      case _EventMenuAction.edit:
        _showEditor(context, event);
        return;
      case _EventMenuAction.delete:
        _confirmDelete(context, event);
        return;
    }
  }

  static String _duration(Duration value) =>
      '${value.inHours.toString().padLeft(2, '0')}:${(value.inMinutes % 60).toString().padLeft(2, '0')}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';
  Future<void> _run(
    BuildContext context,
    Future<String?> Function() action,
  ) async {
    final error = await action();
    if (error != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  void _showEditor(BuildContext context, JaxEvent? event) => showDialog<void>(
    context: context,
    builder: (_) => _EventEditor(controller: controller, event: event),
  );
  Future<void> _confirmDelete(BuildContext context, JaxEvent event) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除事件'),
        content: Text('确定删除“${event.name}”吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await _run(context, () => controller.delete(event.id));
    }
  }
}

enum _EventMenuAction { hierarchy, moveUp, moveDown, edit, delete }

class _EventEditor extends StatefulWidget {
  const _EventEditor({required this.controller, this.event});
  final EventController controller;
  final JaxEvent? event;
  @override
  State<_EventEditor> createState() => _EventEditorState();
}

class _EventEditorState extends State<_EventEditor> {
  late final TextEditingController _text = TextEditingController(
    text: widget.event?.name,
  );
  String? _error;
  bool _busy = false;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.event == null ? '新建事件' : '编辑事件'),
    content: TextField(
      controller: _text,
      autofocus: true,
      decoration: InputDecoration(labelText: '事件名称', errorText: _error),
      onSubmitted: _busy ? null : (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: _busy ? null : _submit,
        child: Text(widget.event == null ? '创建' : '保存'),
      ),
    ],
  );
  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = widget.event == null
        ? await widget.controller.create(_text.text)
        : await widget.controller.edit(widget.event!.id, _text.text);
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context);
    } else {
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }
}
