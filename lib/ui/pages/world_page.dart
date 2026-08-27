import 'package:flutter/material.dart';

import '../../core/entities/category.dart';
import '../../core/entities/jax_event.dart';
import '../../core/entities/world_display_state.dart';
import '../../core/entities/event_status.dart';
import '../../core/preferences/world_category_collapse_store.dart';
import '../controllers/event_controller.dart';
import '../widgets/category_selector.dart';
import '../widgets/event_more_menu_button.dart';
import '../widgets/event_reorder_buttons.dart';
import 'event_hierarchy_dialog.dart';
import 'history_detail_dialog.dart';

class WorldPage extends StatefulWidget {
  const WorldPage({
    required this.controller,
    required this.worldCategoryCollapseStore,
    super.key,
  });
  final EventController controller;
  final WorldCategoryCollapseStore worldCategoryCollapseStore;
  @override
  State<WorldPage> createState() => _WorldPageState();
}

class _WorldPageState extends State<WorldPage> {
  final Set<String> _collapsed = {};
  var _preferencesReady = false;
  Future<void> _preferenceWriteTail = Future.value();

  @override
  void initState() {
    super.initState();
    _loadCollapsedCategories();
  }

  Future<void> _loadCollapsedCategories() async {
    Set<String> collapsed = const {};
    try {
      collapsed = await widget.worldCategoryCollapseStore
          .loadCollapsedSectionKeys();
    } catch (_) {
      // A preference read must not prevent World from using its compatible
      // default: all sections expanded.
    }
    if (!mounted) return;
    setState(() {
      _collapsed.addAll(collapsed);
      _preferencesReady = true;
    });
  }

  void _toggleCategory(String? categoryId) {
    final key = WorldCategoryCollapseStore.sectionKey(categoryId);
    final collapsed = !_collapsed.contains(key);
    setState(() {
      if (collapsed) {
        _collapsed.add(key);
      } else {
        _collapsed.remove(key);
      }
    });
    _preferenceWriteTail = _preferenceWriteTail.then<void>(
      (_) => widget.worldCategoryCollapseStore.setCollapsed(key, collapsed),
      onError: (_, _) =>
          widget.worldCategoryCollapseStore.setCollapsed(key, collapsed),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      if (widget.controller.loading || !_preferencesReady) {
        return const Center(child: CircularProgressIndicator());
      }
      final roots = widget.controller.worldEvents
          .where((e) => e.parentEventId == null)
          .toList();
      final categoriesById = {
        for (final category in widget.controller.categories)
          category.id: category,
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
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const ValueKey('world-new-event'),
                  onPressed: () => _createEvent(context),
                  icon: const Icon(Icons.add),
                  label: const Text('新建事件'),
                ),
                FilledButton.tonalIcon(
                  key: const ValueKey('world-new-category'),
                  onPressed: () => _createCategory(context),
                  icon: const Icon(Icons.create_new_folder_outlined),
                  label: const Text('新建分类'),
                ),
              ],
            ),
          ),
          for (final key in keys)
            if (key != null || groups[key]?.isNotEmpty == true) ...[
              _header(context, key, categoriesById[key]),
              if (!_collapsed.contains(
                WorldCategoryCollapseStore.sectionKey(key),
              ))
                for (final root in groups[key] ?? const <JaxEvent>[])
                  ..._tree(context, root),
            ],
        ],
      );
    },
  );

  Widget _header(BuildContext c, String? id, Category? cat) {
    final i = cat == null ? -1 : widget.controller.categories.indexOf(cat);
    final k = WorldCategoryCollapseStore.sectionKey(id);
    final colors = Theme.of(c).colorScheme;
    return Container(
      key: ValueKey('world-category-$id'),
      margin: const EdgeInsets.only(top: 24, bottom: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(4, 4, 0, 6),
        leading: IconButton(
          key: ValueKey('world-category-toggle-$id'),
          tooltip: _collapsed.contains(k) ? '展开分类' : '折叠分类',
          icon: Icon(
            _collapsed.contains(k) ? Icons.chevron_right : Icons.expand_more,
          ),
          onPressed: () => _toggleCategory(id),
        ),
        title: Text(
          cat?.name ?? '未分类',
          style: Theme.of(c).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        trailing: cat == null
            ? null
            : Opacity(
                opacity: .62,
                child: PopupMenuButton<_CatAction>(
                  key: ValueKey('world-category-more-$id'),
                  tooltip: '分类操作',
                  onSelected: (a) => _catAction(c, cat, i, a),
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: _CatAction.rename,
                      child: ListTile(
                        leading: Icon(Icons.edit),
                        title: Text('重命名'),
                      ),
                    ),
                    if (i > 0)
                      const PopupMenuItem(
                        value: _CatAction.up,
                        child: ListTile(
                          leading: Icon(Icons.arrow_upward),
                          title: Text('上移'),
                        ),
                      ),
                    if (i < widget.controller.categories.length - 1)
                      const PopupMenuItem(
                        value: _CatAction.down,
                        child: ListTile(
                          leading: Icon(Icons.arrow_downward),
                          title: Text('下移'),
                        ),
                      ),
                    const PopupMenuItem(
                      value: _CatAction.delete,
                      child: ListTile(
                        leading: Icon(Icons.delete_outline),
                        title: Text('删除分类'),
                      ),
                    ),
                  ],
                ),
              ),
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
    final displayState = widget.controller.worldDisplayStateFor(e.id);
    final state = _state(displayState);
    final depth = widget.controller.hierarchyDepthFor(e.id);
    final root = e.parentEventId == null;
    final active =
        displayState == WorldDisplayState.running ||
        displayState == WorldDisplayState.progressing;
    final completed = displayState == WorldDisplayState.completed;
    final actions = <PopupMenuEntry<_WorldAction>>[
      if (e.status != EventStatus.completed &&
          !widget.controller.isPlannedToday(e.id))
        PopupMenuItem(
          key: ValueKey('world-add-today-${e.id}'),
          value: _WorldAction.addToday,
          child: const ListTile(
            leading: Icon(Icons.today),
            title: Text('加入今日'),
          ),
        ),
      if (widget.controller.isPlannedToday(e.id) &&
          e.status != EventStatus.running &&
          e.status != EventStatus.completed)
        PopupMenuItem(
          key: ValueKey('world-remove-today-${e.id}'),
          value: _WorldAction.removeToday,
          child: const ListTile(
            leading: Icon(Icons.today_outlined),
            title: Text('移出今日'),
          ),
        ),
      if (e.status == EventStatus.pending)
        PopupMenuItem(
          key: ValueKey('start-${e.id}'),
          value: _WorldAction.start,
          child: ListTile(leading: Icon(Icons.play_arrow), title: Text('开始')),
        ),
      if (e.status == EventStatus.paused || e.status == EventStatus.waiting)
        PopupMenuItem(
          key: ValueKey('resume-${e.id}'),
          value: _WorldAction.resume,
          child: ListTile(leading: Icon(Icons.play_arrow), title: Text('恢复')),
        ),
      if (e.status == EventStatus.running)
        PopupMenuItem(
          key: ValueKey('pause-${e.id}'),
          value: _WorldAction.pause,
          child: ListTile(leading: Icon(Icons.pause), title: Text('暂停')),
        ),
      if (e.status == EventStatus.completed)
        PopupMenuItem(
          key: ValueKey('world-restore-${e.id}'),
          value: _WorldAction.restore,
          child: ListTile(leading: Icon(Icons.restore), title: Text('恢复事件')),
        ),
      if (e.status == EventStatus.completed)
        PopupMenuItem(
          key: ValueKey('world-investment-${e.id}'),
          value: _WorldAction.investment,
          child: ListTile(
            leading: Icon(Icons.analytics_outlined),
            title: Text('投入详情'),
          ),
        ),
      if (e.status == EventStatus.running || e.status == EventStatus.waiting)
        PopupMenuItem(
          key: ValueKey('complete-${e.id}'),
          value: _WorldAction.complete,
          child: const ListTile(leading: Icon(Icons.check), title: Text('完成')),
        ),
      if (e.status == EventStatus.running || e.status == EventStatus.paused)
        PopupMenuItem(
          key: ValueKey('wait-${e.id}'),
          value: _WorldAction.wait,
          child: const ListTile(
            leading: Icon(Icons.hourglass_empty),
            title: Text('设为等待'),
          ),
        ),
      PopupMenuItem(
        key: ValueKey('hierarchy-${e.id}'),
        value: _WorldAction.hierarchy,
        child: ListTile(
          leading: Icon(Icons.account_tree_outlined),
          title: Text('层级详情'),
        ),
      ),
      PopupMenuItem(
        key: ValueKey('edit-${e.id}'),
        value: _WorldAction.edit,
        child: ListTile(leading: Icon(Icons.edit), title: Text('编辑事件')),
      ),
      if (e.parentEventId == null)
        const PopupMenuItem(
          value: _WorldAction.category,
          child: ListTile(
            leading: Icon(Icons.folder_outlined),
            title: Text('设置分类'),
          ),
        ),
      if (e.status == EventStatus.completed && !child)
        PopupMenuItem(
          key: ValueKey('world-delete-history-${e.id}'),
          value: _WorldAction.deleteHistory,
          child: ListTile(
            leading: Icon(Icons.delete_outline),
            title: Text('删除历史记录'),
          ),
        ),
      if (e.status != EventStatus.running &&
          e.status != EventStatus.completed &&
          !child)
        PopupMenuItem(
          key: ValueKey('delete-${e.id}'),
          value: _WorldAction.delete,
          child: const ListTile(
            leading: Icon(Icons.delete_outline),
            title: Text('删除事件'),
          ),
        ),
    ];
    return _WorldEventNode(
      key: ValueKey('world-node-${e.id}'),
      depth: depth,
      root: root,
      active: active,
      completed: completed,
      child: _WorldNodeRow(
        root: root,
        active: active,
        completed: completed,
        leading: child
            ? IconButton(
                key: ValueKey('world-toggle-${e.id}'),
                tooltip: _collapsed.contains(e.id) ? '展开下层事件' : '折叠下层事件',
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
            : const SizedBox(width: 48, height: 48),
        name: e.name,
        statusIcon: state.$1,
        statusLabel: state.$2,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            EventReorderButtons(
              controller: widget.controller,
              eventId: e.id,
              upKey: ValueKey('world-move-up-${e.id}'),
              downKey: ValueKey('world-move-down-${e.id}'),
              compact: true,
            ),
            EventMoreMenuButton<_WorldAction>(
              key: ValueKey('world-more-${e.id}'),
              compact: true,
              onSelected: (a) => _select(c, e, a),
              itemBuilder: (_) => actions,
            ),
          ],
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
      case _WorldAction.edit:
        _edit(c, e);
      case _WorldAction.category:
        _assign(c, e);
      case _WorldAction.restore:
        _confirmRestore(c, e);
      case _WorldAction.investment:
        showHistoryDetailDialog(c, controller: widget.controller, event: e);
      case _WorldAction.deleteHistory:
        _confirmDeleteHistory(c, e);
      case _WorldAction.addToday:
        widget.controller.addToToday(e.id);
      case _WorldAction.removeToday:
        widget.controller.removeFromToday(e.id);
      case _WorldAction.start:
        widget.controller.start(e.id);
      case _WorldAction.resume:
        widget.controller.resume(e.id);
      case _WorldAction.pause:
        widget.controller.pause(e.id);
      case _WorldAction.complete:
        widget.controller.complete(e.id);
      case _WorldAction.wait:
        widget.controller.wait(e.id);
      case _WorldAction.delete:
        _confirmDelete(c, e);
    }
  }

  Future<void> _confirmRestore(BuildContext c, JaxEvent e) async {
    final confirmed = await showDialog<bool>(
      context: c,
      builder: (dialogContext) => AlertDialog(
        title: const Text('恢复事件'),
        content: Text('恢复“${e.name}”后，该事件将重新进入事件列表，原有执行记录会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('恢复事件'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final error = await widget.controller.restore(e.id);
      if (error != null && c.mounted) {
        ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(error)));
      }
    }
  }

  Future<void> _confirmDeleteHistory(BuildContext c, JaxEvent e) async {
    final confirmed = await showDialog<bool>(
      context: c,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除历史记录'),
        content: Text('确定删除“${e.name}”及其执行记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final error = await widget.controller.deleteHistory(e.id);
      if (error != null && c.mounted) {
        ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(error)));
      }
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

  Future<void> _createEvent(BuildContext c) async {
    final text = TextEditingController();
    String? error;
    String? parentId;
    String? selectedRootCategoryId;
    await showDialog<void>(
      context: c,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final parents = widget.controller.worldEvents
              .where((event) => event.status != EventStatus.completed)
              .toList(growable: false);
          final inheritedCategoryId = parentId == null
              ? null
              : _rootCategoryId(parentId!);
          return AlertDialog(
            title: const Text('新建事件'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: text,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: '事件名称',
                      errorText: error,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    key: const ValueKey('world-create-parent'),
                    initialValue: parentId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '上层事件'),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('无（顶级事件）'),
                      ),
                      ...parents.map(
                        (event) => DropdownMenuItem(
                          value: event.id,
                          child: Text(
                            event.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) => setDialogState(() {
                      parentId = value;
                      error = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                  CategorySelector(
                    selectorKey: const ValueKey('world-create-category'),
                    categories: widget.controller.categories,
                    value: parentId == null
                        ? selectedRootCategoryId
                        : inheritedCategoryId,
                    enabled: parentId == null,
                    helperText: parentId == null ? null : '由上层事件继承',
                    onChanged: (value) => setDialogState(() {
                      selectedRootCategoryId = value;
                      error = null;
                    }),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () async {
                  final result = await widget.controller.create(
                    text.text,
                    parentEventId: parentId,
                    categoryId: parentId == null
                        ? selectedRootCategoryId
                        : null,
                  );
                  if (!context.mounted) return;
                  if (result == null) {
                    Navigator.pop(context);
                  } else {
                    setDialogState(() => error = result);
                  }
                },
                child: const Text('创建'),
              ),
            ],
          );
        },
      ),
    );
  }

  String? _rootCategoryId(String eventId) {
    final events = {
      for (final event in widget.controller.worldEvents) event.id: event,
    };
    var current = events[eventId];
    final visited = <String>{};
    while (current != null &&
        current.parentEventId != null &&
        visited.add(current.id)) {
      current = events[current.parentEventId];
    }
    return current?.categoryId;
  }

  Future<void> _confirmDelete(BuildContext c, JaxEvent e) async {
    final confirmed = await showDialog<bool>(
      context: c,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除事件'),
        content: Text('确定删除“${e.name}”吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.controller.delete(e.id);
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
    if (id != null) {
      await widget.controller.assignCategory(e.id, id.isEmpty ? null : id);
    }
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

class _WorldNodeRow extends StatelessWidget {
  const _WorldNodeRow({
    required this.root,
    required this.active,
    required this.completed,
    required this.leading,
    required this.name,
    required this.statusIcon,
    required this.statusLabel,
    required this.trailing,
  });

  final bool root;
  final bool active;
  final bool completed;
  final Widget leading;
  final String name;
  final IconData statusIcon;
  final String statusLabel;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = Text(
      name,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodyLarge?.copyWith(
        fontWeight: active || root ? FontWeight.w600 : FontWeight.w400,
      ),
    );
    final status = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(statusIcon, size: 15),
        const SizedBox(width: 4),
        Text(statusLabel, style: theme.textTheme.bodySmall),
      ],
    );
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: root || active ? 54 : 48),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          leading,
          const SizedBox(width: 4),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => constraints.maxWidth >= 220
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(fit: FlexFit.loose, child: title),
                        const SizedBox(width: 10),
                        status,
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [title, status],
                    ),
            ),
          ),
          const SizedBox(width: 4),
          trailing,
        ],
      ),
    );
  }
}

enum _WorldAction {
  addToday,
  removeToday,
  start,
  resume,
  pause,
  complete,
  wait,
  delete,
  hierarchy,
  edit,
  category,
  restore,
  investment,
  deleteHistory,
}

enum _CatAction { rename, up, down, delete }

class _WorldEventNode extends StatefulWidget {
  const _WorldEventNode({
    required super.key,
    required this.depth,
    required this.root,
    required this.active,
    required this.completed,
    required this.child,
  });

  final int depth;
  final bool root;
  final bool active;
  final bool completed;
  final Widget child;

  @override
  State<_WorldEventNode> createState() => _WorldEventNodeState();
}

class _WorldEventNodeState extends State<_WorldEventNode> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final emphasis = widget.active
        ? colors.primary
        : widget.completed
        ? colors.outlineVariant
        : colors.outlineVariant;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Opacity(
        opacity: widget.completed ? .58 : 1,
        child: Container(
          margin: EdgeInsets.only(top: widget.root ? 6 : 0),
          padding: EdgeInsets.only(
            left: (widget.depth * 24.0).clamp(0.0, 120.0),
          ),
          decoration: BoxDecoration(
            color: widget.active
                ? colors.primary.withValues(alpha: .06)
                : _hovering
                ? colors.onSurface.withValues(alpha: .025)
                : null,
            border: widget.depth == 0 && !widget.active
                ? null
                : Border(
                    left: BorderSide(
                      color: emphasis,
                      width: widget.active ? 2 : 1,
                    ),
                  ),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
