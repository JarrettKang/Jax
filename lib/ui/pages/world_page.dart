import 'package:flutter/material.dart';

import '../../core/entities/jax_event.dart';
import '../../core/entities/world_display_state.dart';
import '../controllers/event_controller.dart';
import 'event_hierarchy_dialog.dart';

class WorldPage extends StatefulWidget {
  const WorldPage({required this.controller, super.key});
  final EventController controller;
  @override
  State<WorldPage> createState() => _WorldPageState();
}

class _WorldPageState extends State<WorldPage> {
  final Set<String> _collapsed = <String>{};

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      if (widget.controller.loading) {
        return const Center(child: CircularProgressIndicator());
      }
      final visible = <JaxEvent>[];
      final hidden = <String>{};
      for (final event in widget.controller.worldEvents) {
        if (event.parentEventId != null &&
            hidden.contains(event.parentEventId)) {
          hidden.add(event.id);
          continue;
        }
        visible.add(event);
        if (_collapsed.contains(event.id)) hidden.add(event.id);
      }
      return ListView(
        key: const ValueKey('world-tree'),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        children: [for (final event in visible) _node(context, event)],
      );
    },
  );

  Widget _node(BuildContext context, JaxEvent event) {
    final hasChildren = widget.controller.hasDirectChildren(event.id);
    final collapsed = _collapsed.contains(event.id);
    final depth = widget.controller.hierarchyDepthFor(event.id);
    final status = _status(widget.controller.worldDisplayStateFor(event.id));
    return Padding(
      key: ValueKey('world-node-${event.id}'),
      padding: EdgeInsets.only(left: (depth * 24.0).clamp(0.0, 120.0)),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        leading: hasChildren
            ? IconButton(
                key: ValueKey('world-toggle-${event.id}'),
                tooltip: collapsed ? '展开' : '折叠',
                icon: Icon(collapsed ? Icons.chevron_right : Icons.expand_more),
                onPressed: () => setState(() {
                  if (collapsed) {
                    _collapsed.remove(event.id);
                  } else {
                    _collapsed.add(event.id);
                  }
                }),
              )
            : const SizedBox(width: 48),
        title: Text(event.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(status.$1, size: 16),
            const SizedBox(width: 4),
            Text(status.$2),
          ],
        ),
        trailing: PopupMenuButton<_WorldAction>(
          key: ValueKey('world-more-${event.id}'),
          tooltip: '更多操作',
          onSelected: (action) => _select(context, event, action),
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: _WorldAction.hierarchy,
              child: Text('层级详情'),
            ),
            if (widget.controller.siblingIndexFor(event.id) > 0)
              const PopupMenuItem(value: _WorldAction.up, child: Text('上移')),
            if (widget.controller.siblingIndexFor(event.id) >= 0 &&
                widget.controller.siblingIndexFor(event.id) <
                    widget.controller.siblingCountFor(event.id) - 1)
              const PopupMenuItem(value: _WorldAction.down, child: Text('下移')),
            const PopupMenuItem(value: _WorldAction.edit, child: Text('编辑事件')),
          ],
        ),
      ),
    );
  }

  (IconData, String) _status(WorldDisplayState status) => switch (status) {
    WorldDisplayState.pending => (Icons.radio_button_unchecked, '未开始'),
    WorldDisplayState.paused => (Icons.pause_circle_outline, '已暂停'),
    WorldDisplayState.running => (Icons.radio_button_checked, '正在执行'),
    WorldDisplayState.progressing => (Icons.adjust, '推进中'),
    WorldDisplayState.waiting => (Icons.hourglass_empty, '等待中'),
    WorldDisplayState.completed => (Icons.check_circle_outline, '已完成'),
  };

  void _select(BuildContext context, JaxEvent event, _WorldAction action) {
    switch (action) {
      case _WorldAction.hierarchy:
        showEventHierarchyDialog(
          context,
          controller: widget.controller,
          event: event,
        );
      case _WorldAction.up:
        widget.controller.moveUp(event.id);
      case _WorldAction.down:
        widget.controller.moveDown(event.id);
      case _WorldAction.edit:
        _edit(context, event);
    }
  }

  Future<void> _edit(BuildContext context, JaxEvent event) async {
    final text = TextEditingController(text: event.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑事件'),
        content: TextField(controller: text, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, text.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    text.dispose();
    if (name != null) await widget.controller.edit(event.id, name);
  }
}

enum _WorldAction { hierarchy, up, down, edit }
