import 'package:flutter/material.dart';

import '../../core/entities/category.dart';
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
  final Set<String> _collapsed = {};
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      if (widget.controller.loading)
        return const Center(child: CircularProgressIndicator());
      final roots = widget.controller.worldEvents
          .where((e) => e.parentEventId == null)
          .toList();
      final categoriesById = {
        for (final category in widget.controller.categories) category.id: category,
      };
      final groups = <String?, List<JaxEvent>>{};
      for (final event in roots) {
        // `null` is the deliberate representation of the virtual
        // "未分类" section.  A stale category reference is also displayed
        // there: it must never make a World rebuild depend on a record that
        // no longer exists (for example while a category deletion reloads).
        final groupId = categoriesById.containsKey(event.categoryId)
            ? event.categoryId
            : null;
        groups.putIfAbsent(groupId, () => []).add(event);
      }
      final keys = <String?>[
        ...widget.controller.categories.map((c) => c.id),
        if (groups.containsKey(null)) null,
      ];
      return ListView(
        key: const ValueKey('world-tree'),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              key: const ValueKey('world-new-category'),
              onPressed: () => _createCategory(context),
              icon: const Icon(Icons.create_new_folder_outlined),
              label: const Text('新建分类'),
            ),
          ),
          for (final key in keys)
            if (key != null || groups[key]?.isNotEmpty == true) ...[
              _header(context, key, categoriesById[key]),
              if (!_collapsed.contains('cat:$key'))
                for (final root in groups[key] ?? const <JaxEvent>[])
                  ..._tree(context, root),
            ],
        ],
      );
    },
  );

  Widget _header(BuildContext c, String? id, Category? cat) {
    final i = cat == null ? -1 : widget.controller.categories.indexOf(cat);
    final k = 'cat:$id';
    return ListTile(
      key: ValueKey('world-category-$id'),
      contentPadding: const EdgeInsets.fromLTRB(4, 20, 0, 4),
      leading: IconButton(
        key: ValueKey('world-category-toggle-$id'),
        icon: Icon(
          _collapsed.contains(k) ? Icons.chevron_right : Icons.expand_more,
        ),
        onPressed: () => setState(
          () =>
              _collapsed.contains(k) ? _collapsed.remove(k) : _collapsed.add(k),
        ),
      ),
      title: Text(
        cat?.name ?? '未分类',
        style: Theme.of(c).textTheme.titleLarge,
      ),
      trailing: cat == null
          ? null
          : PopupMenuButton<_CatAction>(
              key: ValueKey('world-category-more-$id'),
              onSelected: (a) => _catAction(c, cat, i, a),
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: _CatAction.rename,
                  child: Text('重命名'),
                ),
                if (i > 0)
                  const PopupMenuItem(value: _CatAction.up, child: Text('上移')),
                if (i < widget.controller.categories.length - 1)
                  const PopupMenuItem(
                    value: _CatAction.down,
                    child: Text('下移'),
                  ),
                const PopupMenuItem(
                  value: _CatAction.delete,
                  child: Text('删除分类'),
                ),
              ],
            ),
    );
  }

  Iterable<Widget> _tree(BuildContext c, JaxEvent root) {
    final result = <JaxEvent>[];
    final hidden = <String>{};
    for (final e in widget.controller.worldEvents.where(
      (x) => x.id == root.id || _under(x, root.id),
    )) {
      if (e.id != root.id && hidden.contains(e.parentEventId)) {
        hidden.add(e.id);
        continue;
      }
      result.add(e);
      if (_collapsed.contains(e.id)) hidden.add(e.id);
    }
    return [for (final e in result) _node(c, e)];
  }

  bool _under(JaxEvent e, String root) {
    var p = e.parentEventId;
    final seen = <String>{};
    while (p != null && seen.add(p)) {
      if (p == root) return true;
      p = widget.controller.worldEvents
          .where((x) => x.id == p)
          .firstOrNull
          ?.parentEventId;
    }
    return false;
  }

  Widget _node(BuildContext c, JaxEvent e) {
    final child = widget.controller.hasDirectChildren(e.id);
    final state = _state(widget.controller.worldDisplayStateFor(e.id));
    final actions = <PopupMenuEntry<_WorldAction>>[
      const PopupMenuItem(value: _WorldAction.hierarchy, child: Text('层级详情')),
      if (widget.controller.siblingIndexFor(e.id) > 0)
        const PopupMenuItem(value: _WorldAction.up, child: Text('上移')),
      if (widget.controller.siblingIndexFor(e.id) <
          widget.controller.siblingCountFor(e.id) - 1)
        const PopupMenuItem(value: _WorldAction.down, child: Text('下移')),
      const PopupMenuItem(value: _WorldAction.edit, child: Text('编辑事件')),
      if (e.parentEventId == null)
        const PopupMenuItem(value: _WorldAction.category, child: Text('设置分类')),
    ];
    return Padding(
      key: ValueKey('world-node-${e.id}'),
      padding: EdgeInsets.only(
        left: (widget.controller.hierarchyDepthFor(e.id) * 24.0).clamp(
          0.0,
          120.0,
        ),
      ),
      child: ListTile(
        dense: true,
        leading: child
            ? IconButton(
                key: ValueKey('world-toggle-${e.id}'),
                icon: Icon(
                  _collapsed.contains(e.id)
                      ? Icons.chevron_right
                      : Icons.expand_more,
                ),
                onPressed: () => setState(
                  () => _collapsed.contains(e.id)
                      ? _collapsed.remove(e.id)
                      : _collapsed.add(e.id),
                ),
              )
            : const SizedBox(width: 48),
        title: Text(e.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(state.$1, size: 16),
            const SizedBox(width: 4),
            Text(state.$2),
          ],
        ),
        trailing: PopupMenuButton<_WorldAction>(
          key: ValueKey('world-more-${e.id}'),
          onSelected: (a) => _select(c, e, a),
          itemBuilder: (_) => actions,
        ),
      ),
    );
  }

  (IconData, String) _state(WorldDisplayState s) => switch (s) {
    WorldDisplayState.pending => (Icons.radio_button_unchecked, '未开始'),
    WorldDisplayState.paused => (Icons.pause_circle_outline, '已暂停'),
    WorldDisplayState.running => (Icons.radio_button_checked, '正在执行'),
    WorldDisplayState.progressing => (Icons.adjust, '推进中'),
    WorldDisplayState.waiting => (Icons.hourglass_empty, '等待中'),
    WorldDisplayState.completed => (Icons.check_circle_outline, '已完成'),
  };
  void _select(BuildContext c, JaxEvent e, _WorldAction a) {
    switch (a) {
      case _WorldAction.hierarchy:
        showEventHierarchyDialog(c, controller: widget.controller, event: e);
      case _WorldAction.up:
        widget.controller.moveUp(e.id);
      case _WorldAction.down:
        widget.controller.moveDown(e.id);
      case _WorldAction.edit:
        _edit(c, e);
      case _WorldAction.category:
        _assign(c, e);
    }
  }

  Future<void> _edit(BuildContext c, JaxEvent e) async {
    final n = await _name(c, '编辑事件', e.name);
    if (n != null) await widget.controller.edit(e.id, n);
  }

  Future<void> _createCategory(BuildContext c) async {
    final n = await _name(c, '新建分类', null);
    if (n != null) await widget.controller.createCategory(n);
  }

  Future<void> _catAction(
    BuildContext c,
    Category x,
    int i,
    _CatAction a,
  ) async {
    switch (a) {
      case _CatAction.rename:
        final n = await _name(c, '重命名分类', x.name);
        if (n != null) await widget.controller.renameCategory(x.id, n);
      case _CatAction.up:
        await widget.controller.reorderCategory(x.id, i - 1);
      case _CatAction.down:
        await widget.controller.reorderCategory(x.id, i + 1);
      case _CatAction.delete:
        await widget.controller.deleteCategory(x.id);
    }
  }

  Future<void> _assign(BuildContext c, JaxEvent e) async {
    final id = await showDialog<String?>(
      context: c,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('设置分类'),
        children: [
          for (final x in widget.controller.categories)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, x.id),
              child: Text(x.name),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, ''),
            child: const Text('未分类'),
          ),
        ],
      ),
    );
    if (id != null)
      await widget.controller.assignCategory(e.id, id.isEmpty ? null : id);
  }

  Future<String?> _name(BuildContext c, String title, String? initial) async {
    final t = TextEditingController(text: initial);
    final r = await showDialog<String>(
      context: c,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(controller: t, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, t.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    return r;
  }
}

enum _WorldAction { hierarchy, up, down, edit, category }

enum _CatAction { rename, up, down, delete }
