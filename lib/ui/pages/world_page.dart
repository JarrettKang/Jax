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
import '../widgets/execution_time_editor.dart';
import '../../core/entities/execution_time_segment.dart';
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
  final Set<String> _collapsedEvents = {};
  final Set<String> _selectedEventIds = {};
  var _showingDetail = false;
  var _selecting = false;
  String? _selectedCategoryId;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      if (widget.controller.loading) {
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
      final overviewKeys = <String?>[
        ...widget.controller.categories.map((c) => c.id),
        if (groups.containsKey(null)) null,
      ];
      if (_showingDetail &&
          _selectedCategoryId != null &&
          !categoriesById.containsKey(_selectedCategoryId)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _leaveDetail();
        });
        return _overview(context, overviewKeys, groups, categoriesById);
      }
      return _showingDetail
          ? _detail(
              context,
              _selectedCategoryId,
              categoriesById[_selectedCategoryId],
              groups[_selectedCategoryId] ?? const <JaxEvent>[],
            )
          : _overview(context, overviewKeys, groups, categoriesById);
    },
  );

  Widget _overview(
    BuildContext context,
    List<String?> keys,
    Map<String?, List<JaxEvent>> groups,
    Map<String, Category> categoriesById,
  ) => ListView(
    key: const ValueKey('world-overview'),
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
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
      if (keys.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 72),
          child: Center(child: Text('你的世界还没有分类')),
        )
      else ...[
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = (constraints.maxWidth / 260).ceil().clamp(1, 4);
            final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.2;
            return GridView.builder(
              key: const ValueKey('world-category-grid'),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: largeText ? .8 : 1.25,
              ),
              itemCount: keys.length,
              itemBuilder: (context, index) {
                final id = keys[index];
                final category = id == null ? null : categoriesById[id];
                final roots = groups[id] ?? const <JaxEvent>[];
                final eventCount = roots.fold<int>(
                  0,
                  (count, root) => count + 1 + _descendantCount(root.id),
                );
                final active = _categoryContainsRunning(roots);
                return _CategoryOverviewCard(
                  key: ValueKey('world-category-$id'),
                  categoryId: id,
                  name: category?.name ?? '未分类',
                  eventCount: eventCount,
                  rootCount: roots.length,
                  active: active,
                  onTap: () => _enterDetail(id),
                  menu: category == null
                      ? null
                      : _categoryMenu(
                          context,
                          category,
                          widget.controller.categories.indexOf(category),
                        ),
                );
              },
            );
          },
        ),
      ],
    ],
  );

  Widget _detail(
    BuildContext context,
    String? categoryId,
    Category? category,
    List<JaxEvent> roots,
  ) => ListView(
    key: const ValueKey('world-tree'),
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
    children: [
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        runSpacing: 4,
        children: [
          TextButton.icon(
            key: const ValueKey('world-back-overview'),
            onPressed: _leaveDetail,
            icon: const Icon(Icons.arrow_back),
            label: const Text('世界'),
          ),
          const Icon(Icons.chevron_right, size: 18),
          Text(
            category?.name ?? '未分类',
            key: const ValueKey('world-detail-title'),
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
      const SizedBox(height: 12),
      _selecting
          ? _selectionToolbar(context, roots)
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const ValueKey('world-new-event'),
                  onPressed: () => _createTopLevelEvent(context, categoryId),
                  icon: const Icon(Icons.add),
                  label: const Text('新建事件'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('world-batch-select'),
                  onPressed: () => setState(() => _selecting = true),
                  icon: const Icon(Icons.checklist),
                  label: const Text('批量选择'),
                ),
              ],
            ),
      if (roots.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 72),
          child: Center(child: Text('这个分类还没有事件')),
        )
      else ...[
        const SizedBox(height: 16),
        for (final root in roots) ..._tree(context, root),
      ],
    ],
  );

  Widget _categoryMenu(BuildContext context, Category category, int index) =>
      PopupMenuButton<_CatAction>(
        key: ValueKey('world-category-more-${category.id}'),
        tooltip: '分类操作',
        onSelected: (action) => _catAction(context, category, index, action),
        itemBuilder: (_) => [
          const PopupMenuItem(
            value: _CatAction.rename,
            child: ListTile(leading: Icon(Icons.edit), title: Text('重命名')),
          ),
          if (index > 0)
            const PopupMenuItem(
              value: _CatAction.up,
              child: ListTile(
                leading: Icon(Icons.arrow_upward),
                title: Text('上移'),
              ),
            ),
          if (index < widget.controller.categories.length - 1)
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
      );

  void _enterDetail(String? categoryId) => setState(() {
    _selectedCategoryId = categoryId;
    _showingDetail = true;
    _selecting = false;
    _selectedEventIds.clear();
  });

  void _leaveDetail() => setState(() {
    _showingDetail = false;
    _selectedCategoryId = null;
    _selecting = false;
    _selectedEventIds.clear();
  });

  Widget _selectionToolbar(BuildContext context, List<JaxEvent> roots) => Wrap(
    key: const ValueKey('world-batch-toolbar'),
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 8,
    runSpacing: 8,
    children: [
      Text(
        '已选择 ${_selectedEventIds.length} 项',
        key: const ValueKey('world-batch-count'),
      ),
      FilledButton.icon(
        key: const ValueKey('world-batch-add-today'),
        onPressed: _selectedEventIds.isEmpty
            ? null
            : () => _addSelectedToToday(context, roots),
        icon: const Icon(Icons.today),
        label: const Text('加入今日'),
      ),
      TextButton(
        key: const ValueKey('world-batch-cancel'),
        onPressed: () => setState(() {
          _selecting = false;
          _selectedEventIds.clear();
        }),
        child: const Text('取消'),
      ),
    ],
  );

  Future<void> _addSelectedToToday(
    BuildContext context,
    List<JaxEvent> roots,
  ) async {
    final ids = [
      for (final root in roots)
        for (final event in _visibleTreeEvents(root))
          if (_selectedEventIds.contains(event.id)) event.id,
    ];
    final selectedCount = ids.length;
    final error = await widget.controller.addManyToToday(ids);
    if (!mounted || !context.mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    setState(() {
      _selecting = false;
      _selectedEventIds.clear();
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('已加入今日 $selectedCount 项')));
  }

  int _descendantCount(String rootId) => widget.controller.worldEvents
      .where((event) => event.id != rootId && _under(event, rootId))
      .length;

  bool _categoryContainsRunning(List<JaxEvent> roots) => roots.any(
    (root) => widget.controller.worldEvents.any(
      (event) =>
          event.status == EventStatus.running &&
          (event.id == root.id || _under(event, root.id)),
    ),
  );

  Iterable<Widget> _tree(BuildContext c, JaxEvent root) {
    return [for (final e in _visibleTreeEvents(root)) _node(c, e)];
  }

  Iterable<JaxEvent> _visibleTreeEvents(JaxEvent root) {
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
      if (_collapsedEvents.contains(e.id)) hidden.add(e.id);
    }
    return result;
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
    final planned = widget.controller.isPlannedToday(e.id);
    final selectable = e.status != EventStatus.completed && !planned;
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
      if (e.status == EventStatus.paused || e.status == EventStatus.completed)
        PopupMenuItem(
          key: ValueKey('world-edit-time-${e.id}'),
          value: _WorldAction.editTime,
          child: const ListTile(
            leading: Icon(Icons.schedule),
            title: Text('编辑执行时间'),
          ),
        ),
      if (e.status == EventStatus.running) ...[
        PopupMenuItem(
          value: _WorldAction.adjustPause,
          child: const ListTile(
            leading: Icon(Icons.more_time),
            title: Text('调整结束并暂停'),
          ),
        ),
        PopupMenuItem(
          value: _WorldAction.adjustComplete,
          child: const ListTile(
            leading: Icon(Icons.task_alt),
            title: Text('调整结束并完成'),
          ),
        ),
      ],
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
      if (e.status != EventStatus.completed)
        PopupMenuItem(
          key: ValueKey('world-create-child-${e.id}'),
          value: _WorldAction.createChild,
          child: const ListTile(
            leading: Icon(Icons.add),
            title: Text('新建下层事件'),
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
        leading: _selecting
            ? Checkbox(
                key: ValueKey('world-batch-checkbox-${e.id}'),
                value: _selectedEventIds.contains(e.id),
                onChanged: selectable
                    ? (selected) => setState(() {
                        if (selected == true) {
                          _selectedEventIds.add(e.id);
                        } else {
                          _selectedEventIds.remove(e.id);
                        }
                      })
                    : null,
              )
            : child
            ? IconButton(
                key: ValueKey('world-toggle-${e.id}'),
                tooltip: _collapsedEvents.contains(e.id) ? '展开下层事件' : '折叠下层事件',
                icon: Icon(
                  _collapsedEvents.contains(e.id)
                      ? Icons.chevron_right
                      : Icons.expand_more,
                ),
                onPressed: () => setState(
                  () => _collapsedEvents.contains(e.id)
                      ? _collapsedEvents.remove(e.id)
                      : _collapsedEvents.add(e.id),
                ),
              )
            : const SizedBox(width: 48, height: 48),
        name: e.name,
        statusIcon: state.$1,
        statusLabel: !_selecting
            ? state.$2
            : planned
            ? '${state.$2} · 已在今日'
            : completed
            ? '${state.$2} · 不可加入'
            : state.$2,
        trailing: _selecting
            ? const SizedBox(width: 8, height: 48)
            : Row(
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
      case _WorldAction.createChild:
        _createChildEvent(c, e);
      case _WorldAction.edit:
        _edit(c, e);
      case _WorldAction.category:
        _assign(c, e);
      case _WorldAction.restore:
        _confirmRestore(c, e);
      case _WorldAction.investment:
        showHistoryDetailDialog(c, controller: widget.controller, event: e);
      case _WorldAction.editTime:
        showExecutionTimeEditor(
          c,
          controller: widget.controller,
          ownerType: ExecutionOwnerType.event,
          ownerId: e.id,
          ownerName: e.name,
          contextLabel: 'Event',
        );
      case _WorldAction.adjustPause:
        _adjustRunning(c, e, false);
      case _WorldAction.adjustComplete:
        _adjustRunning(c, e, true);
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

  Future<void> _adjustRunning(BuildContext c, JaxEvent e, bool complete) async {
    final items = await widget.controller.executionSegments(
      ExecutionOwnerType.event,
      e.id,
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

  Future<void> _createTopLevelEvent(BuildContext c, String? categoryId) =>
      _showCreateEventDialog(c, rootCategoryId: categoryId);

  Future<void> _createChildEvent(BuildContext c, JaxEvent parent) =>
      _showCreateEventDialog(c, parent: parent);

  Future<void> _showCreateEventDialog(
    BuildContext c, {
    JaxEvent? parent,
    String? rootCategoryId,
  }) async {
    final text = TextEditingController();
    String? error;
    await showDialog<void>(
      context: c,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final inheritedCategoryId = parent == null
              ? null
              : _rootCategoryId(parent.id);
          return AlertDialog(
            title: Text(parent == null ? '新建事件' : '新建下层事件'),
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
                  if (parent != null) ...[
                    InputDecorator(
                      key: const ValueKey('world-create-child-parent'),
                      decoration: const InputDecoration(labelText: '上层事件'),
                      child: Text(
                        parent.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  CategorySelector(
                    selectorKey: const ValueKey('world-create-category'),
                    categories: widget.controller.categories,
                    value: parent == null
                        ? rootCategoryId
                        : inheritedCategoryId,
                    enabled: false,
                    helperText: parent == null ? '由当前分类确定' : '由上层事件继承',
                    onChanged: (_) {},
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
                    parentEventId: parent?.id,
                    categoryId: parent == null ? rootCategoryId : null,
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

class _CategoryOverviewCard extends StatefulWidget {
  const _CategoryOverviewCard({
    required super.key,
    required this.categoryId,
    required this.name,
    required this.eventCount,
    required this.rootCount,
    required this.active,
    required this.onTap,
    required this.menu,
  });

  final String? categoryId;
  final String name;
  final int eventCount;
  final int rootCount;
  final bool active;
  final VoidCallback onTap;
  final Widget? menu;

  @override
  State<_CategoryOverviewCard> createState() => _CategoryOverviewCardState();
}

class _CategoryOverviewCardState extends State<_CategoryOverviewCard> {
  var _hovering = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Card(
        elevation: 0,
        color: widget.active
            ? colors.primaryContainer.withValues(alpha: .24)
            : _hovering
            ? colors.surfaceContainerHighest.withValues(alpha: .68)
            : colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: widget.active
                ? colors.primary.withValues(alpha: .72)
                : _hovering
                ? colors.outline.withValues(alpha: .48)
                : colors.outlineVariant,
            width: widget.active ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(
              child: InkWell(
                key: ValueKey('world-category-open-${widget.categoryId}'),
                onTap: widget.onTap,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (widget.active) ...[
                            Icon(
                              Icons.circle,
                              key: ValueKey(
                                'world-category-active-${widget.categoryId}',
                              ),
                              size: 8,
                              color: colors.primary,
                            ),
                            const SizedBox(width: 6),
                          ],
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(
                                right: widget.menu == null ? 0 : 28,
                              ),
                              child: Text(
                                widget.name,
                                key: ValueKey(
                                  'world-category-name-${widget.categoryId}',
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        '${widget.eventCount} 个事件',
                        key: ValueKey(
                          'world-category-event-count-${widget.categoryId}',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${widget.rootCount} 个顶级事件',
                        key: ValueKey(
                          'world-category-root-count-${widget.categoryId}',
                        ),
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (widget.menu case final menu?)
              Positioned(top: 4, right: 4, child: menu),
          ],
        ),
      ),
    );
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
  createChild,
  delete,
  hierarchy,
  edit,
  category,
  restore,
  investment,
  deleteHistory,
  editTime,
  adjustPause,
  adjustComplete,
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
