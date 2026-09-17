import '../theme/desktop_polish.dart';
import '../theme/list_density.dart';

import 'package:flutter/material.dart';

import '../../core/entities/category.dart';
import '../../core/entities/plan.dart';
import '../../core/entities/world_node.dart';
import '../../core/preferences/world_category_collapse_store.dart';
import '../controllers/planning_controller.dart';
import '../widgets/world_node_tree_guide.dart';
import '../widgets/world_node_browsing_row.dart';
import '../widgets/world_node_tree_picker.dart';
import '../widgets/category_color_picker.dart';
import '../theme/world_theme.dart';
import '../theme/home_pilot_theme.dart';
import '../theme/planning_theme.dart';
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
  final Set<String> _updatingAttention = {};

  @override
  void initState() {
    super.initState();
    widget.controller.load();
    widget.worldCategoryCollapseStore.loadCollapsedSectionKeys().then((value) {
      if (mounted) {
        setState(() {
          _collapsedCategories = value;
          _collapsedBranches.addAll(
            value
                .where((key) => key.startsWith('world-branch:'))
                .map((key) => key.substring('world-branch:'.length)),
          );
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) => WorldVisualScope(
    builder: (context) => AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        if (controller.loading && controller.worldNodes.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        return Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: WorldTheme.structuralWidth,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) => ListView(
                  key: const ValueKey('world-node-overview'),
                  padding: WorldTheme.pagePadding(context),
                  children: [
                    Row(
                      children: [
                        Text(
                          '世界',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const Spacer(),
                        TextButton.icon(
                          key: const ValueKey('add-world-category'),
                          onPressed: _addCategory,
                          icon: const Icon(Icons.create_new_folder_outlined),
                          label: const Text('添加分类'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    for (final category in <Category?>[
                      ...controller.categories,
                      null,
                    ])
                      _categorySection(
                        context,
                        category,
                        constraints.maxWidth -
                            WorldTheme.pagePadding(context).horizontal,
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );

  Widget _categorySection(
    BuildContext context,
    Category? category,
    double availableWidth,
  ) {
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
    return Padding(
      key: ValueKey('world-category-${category?.id ?? 'unclassified'}'),
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: WorldRowSurface(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 32,
                          child: Icon(
                            collapsed ? Icons.chevron_right : Icons.expand_more,
                            size: 18,
                            color: HomePilot.textSecondary,
                          ),
                        ),
                        CategoryColorDot(colorKey: category?.colorKey),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              category?.name ?? '未分类',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                        ),
                      ],
                    ),
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
              ),
              Row(
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
                      tooltip: '分类操作',
                      icon: const Icon(Icons.more_vert, size: 18),
                      style: HomePilot.buttonStyle().copyWith(
                        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                      ),
                      onSelected: (action) => _categoryAction(category, action),
                      itemBuilder: (_) => _categoryActions(category),
                    ),
                ],
              ),
            ],
          ),

          if (!collapsed)
            if (roots.isEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(48, 4, 16, 8),
                  child: Text(
                    '暂无世界节点',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              )
            else
              for (var index = 0; index < roots.length; index++)
                _nodeRow(
                  context,
                  availableWidth,
                  roots[index],
                  WorldNodeTreeVisualContext.root(
                    isLastSibling: index == roots.length - 1,
                  ),
                ),
        ],
      ),
    );
  }

  Widget _nodeRow(
    BuildContext context,
    double availableWidth,
    WorldNode node,
    WorldNodeTreeVisualContext visualContext,
  ) {
    final children =
        widget.controller.worldNodes
            .where((value) => value.parentWorldNodeId == node.id)
            .toList()
          ..sort(_nodeOrder);
    final collapsed = _collapsedBranches.contains(node.id);
    final completed = node.status == WorldNodeStatus.completed;
    const levelIndent = WorldTheme.levelIndent;
    const baseIndent = 0.0;
    const leadingWidth = 48.0;
    final depthLimit = WorldTheme.depthLimit(context, availableWidth);
    return Column(
      children: [
        WorldNodeTreeGuideFrame(
          key: ValueKey('world-node-guide-${node.id}'),
          visualContext: visualContext,
          levelIndent: levelIndent,
          baseIndent: baseIndent,
          nodeLeadingWidth: leadingWidth,
          maximumVisualDepth: depthLimit,
          continueAtMaximumDepth: true,
          paintAboveChild: true,
          guideColor: HomePilot.hairlineStrong,
          hasExpandedChildren: !collapsed && children.isNotEmpty,
          child: WorldNodeBrowsingRow(
            density: JaxListDensity.compact,
            key: ValueKey('world-node-${node.id}'),
            mainKey: ValueKey('world-node-main-${node.id}'),
            browseHint: children.isNotEmpty
                ? (collapsed ? '展开下级' : '折叠下级')
                : node.status == WorldNodeStatus.inProgress
                ? (node.isFocused ? '取消关注' : '关注')
                : null,
            hasChildren: children.isNotEmpty,
            indent: visualContext.contentIndent(
              baseIndent: baseIndent,
              levelIndent: levelIndent,
              maximumVisualDepth: depthLimit,
            ),
            leading: children.isEmpty
                ? SizedBox(
                    width: leadingWidth,
                    height: 48,
                    child: Icon(
                      completed ? Icons.check : Icons.circle_outlined,
                      size: completed ? 16 : 8,
                      semanticLabel: completed ? '已完成' : null,
                      color: HomePilot.textSecondary,
                    ),
                  )
                : IconButton(
                    key: ValueKey('world-node-branch-${node.id}'),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: leadingWidth,
                      height: 48,
                    ),
                    tooltip: collapsed ? '展开下级' : '折叠下级',
                    onPressed: () => _toggleBranch(node.id),
                    icon: Icon(
                      collapsed ? Icons.chevron_right : Icons.expand_more,
                    ),
                  ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (completed && children.isNotEmpty)
                      const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: Icon(
                          Icons.check,
                          size: 16,
                          color: HomePilot.textMuted,
                          semanticLabel: '已完成',
                        ),
                      ),
                    if (node.isFocused)
                      const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: Tooltip(
                          message: '关注中',
                          child: Icon(
                            Icons.center_focus_strong,
                            size: 16,
                            color: HomePilot.textMuted,
                          ),
                        ),
                      ),
                    Expanded(
                      child: Text(
                        node.name,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: completed
                                  ? HomePilot.textMuted
                                  : HomePilot.textPrimary,
                              fontWeight: children.isNotEmpty
                                  ? FontWeight.w500
                                  : FontWeight.w400,
                            ),
                      ),
                    ),
                  ],
                ),
                if (visualContext.depth > depthLimit)
                  Text(
                    '第 ${visualContext.depth + 1} 层 · 上层：${widget.controller.nodeFor(node.parentWorldNodeId!)?.name ?? ""}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
            more: PopupMenuButton<String>(
              key: ValueKey('world-node-more-${node.id}'),
              tooltip: '更多操作',
              constraints: const BoxConstraints(minWidth: 160),
              icon: Icon(
                Icons.more_vert,
                size: 18,
                color: HomePilot.textSecondary,
              ),
              style: IconButton.styleFrom(
                minimumSize: const Size(48, 48),
                padding: EdgeInsets.zero,
                tapTargetSize: MaterialTapTargetSize.padded,
              ),
              onSelected: (action) => _nodeAction(node, action),
              itemBuilder: (_) => _actionsFor(node),
            ),
            onBrowse: children.isEmpty ? null : () => _toggleBranch(node.id),
            onAttention: node.status == WorldNodeStatus.inProgress
                ? () => _changeAttention(node.id)
                : null,
          ),
        ),
        if (!collapsed)
          for (var index = 0; index < children.length; index++)
            _nodeRow(
              context,
              availableWidth,
              children[index],
              visualContext.child(isLastSibling: index == children.length - 1),
            ),
      ],
    );
  }

  Future<void> _toggleBranch(String nodeId) async {
    final collapsed = !_collapsedBranches.contains(nodeId);
    setState(() {
      collapsed
          ? _collapsedBranches.add(nodeId)
          : _collapsedBranches.remove(nodeId);
    });
    await widget.worldCategoryCollapseStore.setCollapsed(
      WorldCategoryCollapseStore.branchKey(nodeId),
      collapsed,
    );
  }

  Future<void> _changeAttention(String nodeId, {bool? focused}) async {
    final node = widget.controller.nodeFor(nodeId);
    if (node == null ||
        node.status != WorldNodeStatus.inProgress ||
        !_updatingAttention.add(nodeId)) {
      return;
    }
    try {
      final target = focused ?? !node.isFocused;
      await widget.controller.setWorldNodeFocus(node, target);
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.hideCurrentSnackBar();
        if (target && !node.isFocused) {
          messenger.showSnackBar(
            SnackBar(
              content: Text('已关注 ${node.name}'),
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: '开始规划',
                onPressed: () async {
                  await widget.controller.load();
                  if (!mounted) return;
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PlanDetailPage(
                        controller: widget.controller,
                        worldNodeId: node.id,
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      _updatingAttention.remove(nodeId);
    }
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
      const PopupMenuItem(value: 'open-detail', child: Text('查看详情')),
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
      if (ended.isNotEmpty)
        const PopupMenuItem(value: 'open-history', child: Text('查看历史计划')),
      const PopupMenuDivider(),
      const PopupMenuItem(value: 'add-child', child: Text('添加子节点')),
      const PopupMenuItem(value: 'rename', child: Text('重命名')),
      if (index > 0) const PopupMenuItem(value: 'move-up', child: Text('上移')),
      if (index >= 0 && index < siblings.length - 1)
        const PopupMenuItem(value: 'move-down', child: Text('下移')),
      const PopupMenuItem(value: 'reparent', child: Text('移动到…')),
      const PopupMenuDivider(),
      PopupMenuItem(
        value: completed ? 'restore' : 'complete',
        child: Text(completed ? '恢复节点' : '完成节点'),
      ),
    ];
  }

  Future<void> _nodeAction(WorldNode node, String action) async {
    if (action == 'open-detail') return _openNodeDetail(node);
    if (action == 'focus' || action == 'unfocus') {
      return _changeAttention(node.id, focused: action == 'focus');
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
      const PopupMenuItem(
        value: 'delete',
        child: Text('删除分类', style: TextStyle(color: PlanningTheme.error)),
      ),
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
        builder: (context) => WorldVisualScope(
          builder: (context) => AlertDialog(
            constraints: DesktopPolish.dialog(
              context,
              DesktopDialogSize.confirmation,
            ),
            title: const Text('删除分类？'),
            content: const Text('分类中的根节点与临时事项将移入“未分类”，不会被删除。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: PlanningTheme.destructive,
                child: const Text('删除'),
              ),
            ],
          ),
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
    final effectiveCategoryId = widget.controller.categoryForNode(node)?.id;
    final expandedPath = widget.controller
        .pathFor(node)
        .map((value) => value.id)
        .toSet();
    final target = await showDialog<String?>(
      context: context,
      builder: (dialogContext) => WorldVisualScope(
        builder: (dialogContext) => AlertDialog(
          constraints: DesktopPolish.dialog(
            dialogContext,
            DesktopDialogSize.complex,
          ),
          title: const Text('移动到…'),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          content: SizedBox(
            width: 520,
            height: (MediaQuery.sizeOf(dialogContext).height * .65).clamp(
              0,
              580,
            ),
            child: WorldNodeTreePicker(
              worldVisuals: true,
              header: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    node.name,
                    style: Theme.of(dialogContext).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  WorldRowSurface(
                    onTap: node.parentWorldNodeId == null
                        ? null
                        : () => Navigator.pop(dialogContext, ''),
                    child: ListTile(
                      key: const ValueKey('move-target-root'),
                      contentPadding: EdgeInsets.zero,
                      minTileHeight: 48,
                      title: const Text('无上层（移动为顶级节点）'),
                      subtitle: node.parentWorldNodeId == null
                          ? const Text('当前已是顶级节点')
                          : const Text('保留当前有效分类，并追加到顶级节点末尾'),
                      enabled: node.parentWorldNodeId != null,
                    ),
                  ),
                  const Divider(),
                ],
              ),
              categories: widget.controller.categories,
              worldNodes: widget.controller.worldNodes,
              listKey: const ValueKey('world-move-tree'),
              categoryKeyPrefix: 'move-selector-category-',
              nodeKeyPrefix: 'move-target-',
              branchKeyPrefix: 'move-selector-branch-',
              initiallyExpandedCategoryIds: {effectiveCategoryId},
              initiallyExpandedBranchIds: expandedPath,
              disabledReasonFor: (candidate) {
                if (candidate.id == node.id) return '当前节点';
                if (descendants.contains(candidate.id)) {
                  return '当前节点的下级';
                }
                if (candidate.id == node.parentWorldNodeId) {
                  return '当前上层';
                }
                return null;
              },
              onSelected: (candidate) =>
                  Navigator.pop(dialogContext, candidate.id),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
          ],
        ),
      ),
    );
    if (target != null) {
      await _guard(
        () => widget.controller.moveWorldNode(
          node,
          parentWorldNodeId: target.isEmpty ? null : target,
          categoryId: target.isEmpty ? effectiveCategoryId : null,
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
      builder: (context) => WorldVisualScope(
        builder: (context) => AlertDialog(
          constraints: DesktopPolish.dialog(context, DesktopDialogSize.form),
          title: Text(title),
          scrollable: true,
          content: TextFormField(
            initialValue: initial,
            minLines: 1,
            maxLines: null,
            textInputAction: TextInputAction.done,
            style: Theme.of(context).textTheme.titleMedium,
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
