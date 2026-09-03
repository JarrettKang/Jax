import 'package:flutter/material.dart';

import '../../core/entities/category.dart';
import '../../core/entities/plan.dart';
import '../../core/entities/world_node.dart';
import '../../core/preferences/world_category_collapse_store.dart';
import '../controllers/planning_controller.dart';
import 'planning_page.dart';
import 'world_node_detail_page.dart';

class WorldPage extends StatefulWidget {
  const WorldPage({
    required this.controller,
    required this.worldCategoryCollapseStore,
    super.key,
  });

  final PlanningController controller;
  final WorldCategoryCollapseStore worldCategoryCollapseStore;

  @override
  State<WorldPage> createState() => _WorldPageState();
}

class _WorldPageState extends State<WorldPage> {
  final Set<String> _collapsedBranches = {};
  Set<String> _collapsedCategories = {};

  @override
  void initState() {
    super.initState();
    widget.controller.load();
    widget.worldCategoryCollapseStore.loadCollapsedSectionKeys().then((value) {
      if (mounted) setState(() => _collapsedCategories = value);
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      if (controller.loading && controller.worldNodes.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      return Scaffold(
        body: ListView(
          key: const ValueKey('world-node-overview'),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 96),
          children: [
            Row(
              children: [
                Text('世界', style: Theme.of(context).textTheme.headlineSmall),
                const Spacer(),
                TextButton.icon(
                  key: const ValueKey('add-world-category'),
                  onPressed: _addCategory,
                  icon: const Icon(Icons.create_new_folder_outlined),
                  label: const Text('添加分类'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final category in <Category?>[...controller.categories, null])
              _categorySection(category),
          ],
        ),
      );
    },
  );

  Widget _categorySection(Category? category) {
    final roots =
        widget.controller.worldNodes
            .where(
              (node) =>
                  node.parentWorldNodeId == null &&
                  node.categoryId == category?.id,
            )
            .toList()
          ..sort(_nodeOrder);
    final key = WorldCategoryCollapseStore.sectionKey(category?.id);
    final collapsed = _collapsedCategories.contains(key);
    return Card(
      key: ValueKey('world-category-${category?.id ?? 'unclassified'}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          ListTile(
            leading: Icon(
              collapsed ? Icons.chevron_right : Icons.expand_more,
              color: category == null
                  ? Theme.of(context).colorScheme.outline
                  : Theme.of(context).colorScheme.primary,
            ),
            title: Text(category?.name ?? '未分类'),
            subtitle: Text('${roots.length} 个根节点'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: ValueKey('add-root-${category?.id ?? 'unclassified'}'),
                  tooltip: '添加根节点',
                  onPressed: () => _addNode(categoryId: category?.id),
                  icon: const Icon(Icons.add),
                ),
                if (category != null)
                  PopupMenuButton<String>(
                    key: ValueKey('world-category-more-${category.id}'),
                    onSelected: (action) => _categoryAction(category, action),
                    itemBuilder: (_) => _categoryActions(category),
                  ),
              ],
            ),
            onTap: () async {
              setState(() {
                collapsed
                    ? _collapsedCategories.remove(key)
                    : _collapsedCategories.add(key);
              });
              await widget.worldCategoryCollapseStore.setCollapsed(
                key,
                !collapsed,
              );
            },
          ),
          if (!collapsed)
            if (roots.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 18),
                child: Text('暂无世界节点'),
              )
            else
              for (final root in roots) _nodeRow(root, 0),
        ],
      ),
    );
  }

  Widget _nodeRow(WorldNode node, int depth) {
    final children =
        widget.controller.worldNodes
            .where((value) => value.parentWorldNodeId == node.id)
            .toList()
          ..sort(_nodeOrder);
    final collapsed = _collapsedBranches.contains(node.id);
    final completed = node.status == WorldNodeStatus.completed;
    return Column(
      children: [
        ListTile(
          key: ValueKey('world-node-${node.id}'),
          contentPadding: EdgeInsets.only(left: 12.0 + depth * 24, right: 8),
          leading: children.isEmpty
              ? Icon(
                  completed
                      ? Icons.check_circle_outline
                      : Icons.circle_outlined,
                  size: 20,
                )
              : IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                  onPressed: () => setState(() {
                    collapsed
                        ? _collapsedBranches.remove(node.id)
                        : _collapsedBranches.add(node.id);
                  }),
                  icon: Icon(
                    collapsed ? Icons.chevron_right : Icons.expand_more,
                  ),
                ),
          title: Text(
            node.name,
            style: completed
                ? const TextStyle(decoration: TextDecoration.lineThrough)
                : null,
          ),
          subtitle: Text(_planningState(node)),
          trailing: PopupMenuButton<String>(
            key: ValueKey('world-node-more-${node.id}'),
            onSelected: (action) => _nodeAction(node, action),
            itemBuilder: (_) => _actionsFor(node),
          ),
          onTap: () => _openNodeDetail(node),
        ),
        if (!collapsed)
          for (final child in children) _nodeRow(child, depth + 1),
      ],
    );
  }

  String _planningState(WorldNode node) {
    if (node.status == WorldNodeStatus.completed) return '已完成 · 仅可查看历史计划';
    final attention = node.isFocused ? '关注中 · ' : '';
    if (widget.controller.currentPlanFor(node.id) != null) {
      return '$attention已有当前计划';
    }
    if (widget.controller.hasEndedPlan(node.id)) return '$attention上一轮已结束';
    return '$attention尚无计划';
  }

  List<PopupMenuEntry<String>> _actionsFor(WorldNode node) {
    final completed = node.status == WorldNodeStatus.completed;
    final current = widget.controller.currentPlanFor(node.id);
    final ended = widget.controller.plans
        .where(
          (plan) =>
              plan.worldNodeId == node.id && plan.status == PlanStatus.ended,
        )
        .toList();
    final siblings = _siblings(node);
    final index = siblings.indexWhere((value) => value.id == node.id);
    return [
      if (!completed)
        PopupMenuItem(
          value: node.isFocused ? 'unfocus' : 'focus',
          child: Text(node.isFocused ? '取消关注' : '关注'),
        ),
      if (node.status == WorldNodeStatus.inProgress && current == null)
        PopupMenuItem(
          value: 'create-plan',
          child: Text(ended.isEmpty ? '添加计划' : '添加新一轮计划'),
        ),
      if (current != null)
        const PopupMenuItem(value: 'open-current', child: Text('查看当前计划')),
      if (ended.isNotEmpty)
        const PopupMenuItem(value: 'open-history', child: Text('查看历史计划')),
      const PopupMenuDivider(),
      const PopupMenuItem(value: 'add-child', child: Text('添加子节点')),
      const PopupMenuItem(value: 'rename', child: Text('重命名')),
      if (index > 0) const PopupMenuItem(value: 'move-up', child: Text('上移')),
      if (index >= 0 && index < siblings.length - 1)
        const PopupMenuItem(value: 'move-down', child: Text('下移')),
      const PopupMenuItem(value: 'reparent', child: Text('移动到…')),
      PopupMenuItem(
        value: completed ? 'restore' : 'complete',
        child: Text(completed ? '恢复节点' : '完成节点'),
      ),
    ];
  }

  Future<void> _nodeAction(WorldNode node, String action) async {
    if (action == 'focus' || action == 'unfocus') {
      return _guard(
        () => widget.controller.setWorldNodeFocus(node, action == 'focus'),
      );
    }
    if (action == 'add-child') return _addNode(parent: node);
    if (action == 'rename') return _renameNode(node);
    if (action == 'move-up' || action == 'move-down') {
      final siblings = _siblings(node);
      final index = siblings.indexWhere((value) => value.id == node.id);
      return _guard(
        () => widget.controller.moveWorldNodeOrder(
          node,
          action == 'move-up' ? index - 1 : index + 1,
        ),
      );
    }
    if (action == 'reparent') return _moveNode(node);
    if (action == 'complete' || action == 'restore') {
      return _guard(
        () => widget.controller.setWorldNodeStatus(
          node,
          action == 'complete'
              ? WorldNodeStatus.completed
              : WorldNodeStatus.inProgress,
        ),
      );
    }
    if (action == 'create-plan') {
      await _guard(() async {
        final plan = await widget.controller.createPlan(node);
        if (mounted) await _openPlan(plan);
      });
      return;
    }
    if (action == 'open-current') {
      final plan = widget.controller.currentPlanFor(node.id);
      if (plan != null) await _openPlan(plan);
      return;
    }
    if (action == 'open-history') {
      final plans =
          widget.controller.plans
              .where(
                (plan) =>
                    plan.worldNodeId == node.id &&
                    plan.status == PlanStatus.ended,
              )
              .toList()
            ..sort((a, b) => b.roundNumber.compareTo(a.roundNumber));
      if (plans.isNotEmpty) await _openPlan(plans.first);
    }
  }

  Future<void> _openPlan(Plan plan) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            PlanDetailPage(controller: widget.controller, planId: plan.id),
      ),
    );
    await widget.controller.load();
  }

  Future<void> _openNodeDetail(WorldNode node) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WorldNodeDetailPage(
          controller: widget.controller,
          worldNodeId: node.id,
        ),
      ),
    );
    await widget.controller.load();
  }

  Future<void> _addCategory() async {
    final name = await _nameDialog('添加分类');
    if (name != null) {
      await _guard(() => widget.controller.createCategory(name));
    }
  }

  List<PopupMenuEntry<String>> _categoryActions(Category category) {
    final index = widget.controller.categories.indexWhere(
      (value) => value.id == category.id,
    );
    return [
      const PopupMenuItem(value: 'rename', child: Text('重命名分类')),
      if (index > 0) const PopupMenuItem(value: 'move-up', child: Text('分类上移')),
      if (index >= 0 && index < widget.controller.categories.length - 1)
        const PopupMenuItem(value: 'move-down', child: Text('分类下移')),
      const PopupMenuItem(value: 'delete', child: Text('删除分类')),
    ];
  }

  Future<void> _categoryAction(Category category, String action) async {
    if (action == 'rename') {
      final name = await _nameDialog('重命名分类', initial: category.name);
      if (name != null) {
        await _guard(() => widget.controller.renameCategory(category, name));
      }
      return;
    }
    if (action == 'move-up' || action == 'move-down') {
      final index = widget.controller.categories.indexWhere(
        (value) => value.id == category.id,
      );
      await _guard(
        () => widget.controller.moveCategory(
          category,
          action == 'move-up' ? index - 1 : index + 1,
        ),
      );
      return;
    }
    if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('删除分类？'),
          content: const Text('分类中的根节点与临时事项将移入“未分类”，不会被删除。'),
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
      if (confirmed == true) {
        await _guard(() => widget.controller.deleteCategory(category));
      }
    }
  }

  Future<void> _addNode({WorldNode? parent, String? categoryId}) async {
    final name = await _nameDialog(parent == null ? '添加世界节点' : '添加子节点');
    if (name == null) return;
    await _guard(
      () => widget.controller.createWorldNode(
        name,
        parentWorldNodeId: parent?.id,
        categoryId: categoryId,
      ),
    );
  }

  Future<void> _renameNode(WorldNode node) async {
    final name = await _nameDialog('重命名', initial: node.name);
    if (name != null) {
      await _guard(() => widget.controller.renameWorldNode(node, name));
    }
  }

  Future<void> _moveNode(WorldNode node) async {
    final descendants = <String>{};
    void collect(String parent) {
      for (final child in widget.controller.worldNodes.where(
        (value) => value.parentWorldNodeId == parent,
      )) {
        if (descendants.add(child.id)) collect(child.id);
      }
    }

    collect(node.id);
    final target = await showDialog<(String?, String?)>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移动世界节点'),
        content: SizedBox(
          width: 480,
          height: 480,
          child: ListView(
            children: [
              for (final category in <Category?>[
                ...widget.controller.categories,
                null,
              ])
                ListTile(
                  title: Text('${category?.name ?? '未分类'}（根节点）'),
                  onTap: () => Navigator.pop(context, (null, category?.id)),
                ),
              const Divider(),
              for (final candidate in widget.controller.worldNodes)
                if (candidate.id != node.id &&
                    !descendants.contains(candidate.id))
                  ListTile(
                    title: Text(candidate.name),
                    subtitle: const Text('作为其子节点'),
                    onTap: () => Navigator.pop(context, (candidate.id, null)),
                  ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (target != null) {
      await _guard(
        () => widget.controller.moveWorldNode(
          node,
          parentWorldNodeId: target.$1,
          categoryId: target.$2,
        ),
      );
    }
  }

  List<WorldNode> _siblings(WorldNode node) =>
      widget.controller.worldNodes
          .where(
            (value) => node.parentWorldNodeId != null
                ? value.parentWorldNodeId == node.parentWorldNodeId
                : value.parentWorldNodeId == null &&
                      value.categoryId == node.categoryId,
          )
          .toList()
        ..sort(_nodeOrder);

  Future<String?> _nameDialog(String title, {String initial = ''}) async {
    var text = initial;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextFormField(
          initialValue: initial,
          autofocus: true,
          decoration: const InputDecoration(labelText: '名称'),
          onChanged: (value) => text = value,
          onFieldSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    return result;
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    }
  }

  static int _nodeOrder(WorldNode a, WorldNode b) {
    final order = a.sortOrder.compareTo(b.sortOrder);
    return order != 0 ? order : a.id.compareTo(b.id);
  }
}
