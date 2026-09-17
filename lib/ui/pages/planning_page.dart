import '../theme/desktop_polish.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/entities/plan.dart';
import '../../core/entities/plan_item.dart';
import '../../core/entities/plan_review_note.dart';
import '../../core/entities/jax_event.dart';
import '../../core/entities/world_node.dart';
import '../../core/errors/domain_failure.dart';
import '../controllers/planning_controller.dart';
import '../theme/home_pilot_theme.dart';
import '../theme/planning_theme.dart';
import '../widgets/world_node_tree_picker.dart';
import '../widgets/world_node_ancestry_view.dart';

class PlanningPage extends StatefulWidget {
  const PlanningPage({
    required this.controller,
    this.openRequest,
    this.onOpenRequestConsumed,
    super.key,
  });
  final PlanningController controller;
  final PlanningOpenRequest? openRequest;
  final VoidCallback? onOpenRequestConsumed;

  @override
  State<PlanningPage> createState() => _PlanningPageState();
}

class _PlanningPageState extends State<PlanningPage> {
  PlanningOpenRequest? _handledRequest;

  @override
  void initState() {
    super.initState();
    widget.controller.load();
    _scheduleOpenRequest();
  }

  @override
  void didUpdateWidget(PlanningPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleOpenRequest();
  }

  void _scheduleOpenRequest() {
    final request = widget.openRequest;
    if (request == null || identical(request, _handledRequest)) return;
    _handledRequest = request;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      widget.onOpenRequestConsumed?.call();
      await widget.controller.load();
      if (!mounted) return;
      final plan = widget.controller.plans
          .where((value) => value.id == request.planId)
          .firstOrNull;
      if (plan == null) {
        _showError(context, const DomainFailure('目标计划已不存在'));
        return;
      }
      await _openPlan(plan, openAddItem: request.openAddItem);
    });
  }

  @override
  Widget build(BuildContext context) => PlanningVisualScope(
    builder: (context) => AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        if (controller.loading && controller.plans.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (controller.error != null && controller.plans.isEmpty) {
          return Center(child: Text('无法加载规划：${controller.error}'));
        }
        final workspaces = controller.focusedWorldNodePlanning;
        return Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: ListView(
                key: const ValueKey('planning-overview'),
                padding: PlanningTheme.pagePadding(context),
                children: [
                  Row(
                    children: [
                      Text(
                        '规划',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const Spacer(),
                      OutlinedButton.icon(
                        key: const ValueKey('add-plan'),
                        onPressed: () => _createPlan(context),
                        icon: const Icon(Icons.add),
                        label: const Text('添加计划'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (workspaces.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        '暂无关注中的世界节点。\n去“世界”中关注你现在想推进的节点。',
                        key: ValueKey('planning-no-focused-world-nodes'),
                      ),
                    )
                  else
                    ...workspaces.map(
                      (workspace) => _FocusedWorldNodeTile(
                        workspace: workspace,
                        onOpen: () => _openWorkspace(workspace.node),
                        ancestors: controller
                            .pathFor(workspace.node)
                            .where((node) => node.id != workspace.node.id)
                            .toList(),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );

  Future<void> _createPlan(BuildContext context) async {
    final node = await showDialog<WorldNode>(
      context: context,
      builder: (_) => _WorldNodeSelector(controller: widget.controller),
    );
    if (node == null || !context.mounted) return;
    try {
      final plan = await widget.controller.createPlan(node);
      if (context.mounted) await _openPlan(plan);
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _openWorkspace(WorldNode node) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            PlanDetailPage(controller: widget.controller, worldNodeId: node.id),
      ),
    );
    await widget.controller.load();
  }

  Future<void> _openPlan(Plan plan, {bool openAddItem = false}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlanDetailPage(
          controller: widget.controller,
          planId: plan.id,
          openAddItemOnLaunch: openAddItem,
        ),
      ),
    );
    await widget.controller.load();
  }
}

class PlanningOpenRequest {
  const PlanningOpenRequest({required this.planId, this.openAddItem = false});

  final String planId;
  final bool openAddItem;
}

class _FocusedWorldNodeTile extends StatelessWidget {
  const _FocusedWorldNodeTile({
    required this.workspace,
    required this.ancestors,
    required this.onOpen,
  });
  final FocusedWorldNodePlanning workspace;
  final List<WorldNode> ancestors;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PlanningRowSurface(
      key: ValueKey('focused-world-node-${workspace.node.id}'),
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    workspace.node.name,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                const SizedBox(width: 12),
                const Icon(Icons.chevron_right, size: 22),
              ],
            ),
            const SizedBox(height: 8),
            WorldNodeAncestryView(
              textStyle: theme.textTheme.bodySmall,
              guideColor: HomePilot.hairlineStrong,
              names: [
                workspace.category?.name ?? '未分类',
                ...ancestors.map((node) => node.name),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WorldNodeSelector extends StatelessWidget {
  const _WorldNodeSelector({required this.controller});
  final PlanningController controller;

  @override
  Widget build(BuildContext context) => AlertDialog(
    constraints: DesktopPolish.dialog(context, DesktopDialogSize.complex),
    title: const Text('选择世界节点'),
    content: SizedBox(
      width: 520,
      height: 540,
      child: WorldNodeTreePicker(
        categories: controller.categories,
        worldNodes: controller.worldNodes,
        listKey: const ValueKey('planning-world-node-selector'),
        categoryKeyPrefix: 'planning-selector-category-',
        nodeKeyPrefix: 'select-world-node-',
        branchKeyPrefix: 'planning-selector-branch-',
        disabledReasonFor: (node) {
          if (node.status == WorldNodeStatus.completed) {
            return '已完成：只能查看历史，不能创建计划';
          }
          if (controller.hasCurrentPlan(node.id)) {
            return '已有当前计划：请先查看或结束该轮';
          }
          return null;
        },
        onSelected: (node) => Navigator.pop(context, node),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
    ],
  );
}

class PlanDetailPage extends StatelessWidget {
  const PlanDetailPage({
    required this.controller,
    this.planId,
    this.worldNodeId,
    this.openAddItemOnLaunch = false,
    super.key,
  });
  final PlanningController controller;
  final String? planId;
  final String? worldNodeId;
  final bool openAddItemOnLaunch;

  @override
  Widget build(BuildContext context) => PlanningVisualScope(
    builder: (context) => AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final plan = planId == null
            ? controller.currentPlanFor(worldNodeId!)
            : controller.plans.where((p) => p.id == planId).firstOrNull;
        final node = controller.nodeFor(plan?.worldNodeId ?? worldNodeId ?? '');
        if (node == null || (planId != null && plan == null)) {
          return Scaffold(
            appBar: AppBar(title: const Text('规划')),
            body: const Center(child: Text('目标已不存在，请返回刷新')),
          );
        }
        final history =
            controller.plans
                .where((p) => p.worldNodeId == node.id && !p.isCurrent)
                .toList()
              ..sort((a, b) => b.roundNumber.compareTo(a.roundNumber));
        final items = plan == null
            ? <PlanItem>[]
            : controller.itemsFor(plan.id);
        final reviews = plan == null
            ? <PlanReviewNote>[]
            : controller.reviewNotesFor(plan.id);
        final canBegin = node.status == WorldNodeStatus.inProgress;
        final canAdd = plan?.isCurrent ?? (history.isEmpty && canBegin);
        return Scaffold(
          appBar: AppBar(
            title: const Text('规划'),
            actions: [
              if (plan != null && plan.isCurrent && canBegin && !node.isFocused)
                TextButton.icon(
                  key: const ValueKey('focus-world-node-from-plan'),
                  onPressed: () => _guard(
                    context,
                    () => controller.setWorldNodeFocus(node, true),
                  ),
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('关注节点'),
                ),
              if (plan != null)
                PopupMenuButton<String>(
                  tooltip: '更多操作',
                  icon: const Icon(Icons.more_horiz, size: 18),
                  style: HomePilot.buttonStyle(),
                  key: const ValueKey('plan-more'),
                  onSelected: (v) {
                    if (v == 'rename') _renamePlan(context, plan);
                    if (v == 'end') _endPlan(context, plan, items);
                    if (v == 'delete') _deletePlan(context, plan);
                  },
                  itemBuilder: (_) => [
                    if (plan.isCurrent)
                      const PopupMenuItem(
                        value: 'rename',
                        child: Text('修改计划名称'),
                      ),
                    if (plan.isCurrent)
                      const PopupMenuItem(value: 'end', child: Text('本轮计划结束')),
                    if (controller.canDeletePlan(plan))
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text(
                          '删除整个计划',
                          style: TextStyle(color: PlanningTheme.error),
                        ),
                      ),
                  ],
                ),
            ],
          ),
          body: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: ListView(
                key: const ValueKey('plan-detail'),
                padding: PlanningTheme.pagePadding(context),
                children: [
                  Text(
                    node.name,
                    key: const ValueKey('planning-workspace-title'),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  WorldNodeAncestryView(
                    key: const ValueKey('planning-workspace-ancestry'),
                    names: _workspacePath(controller, node)..removeLast(),
                    textStyle: Theme.of(context).textTheme.bodySmall,
                    guideColor: HomePilot.hairlineStrong,
                  ),
                  const SizedBox(height: 24),
                  Text('计划步骤', style: Theme.of(context).textTheme.titleLarge),
                  if (plan == null && history.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text('上一轮已结束'),
                    ),
                    if (canBegin)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton.tonal(
                          key: const ValueKey('start-planning-round'),
                          onPressed: () => _guard(context, () async {
                            await controller.createPlan(node);
                          }),
                          child: const Text('开始新一轮计划'),
                        ),
                      ),
                  ] else if (items.isEmpty && canAdd)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        plan == null
                            ? '你准备怎么推进它？\n写下第一步就好，不需要一次想完整。'
                            : '这一轮还没有步骤。\n先写下第一件事，之后随时可以补充、调整或删除。',
                      ),
                    ),
                  const SizedBox(height: 12),
                  ...List.generate(
                    items.length,
                    (index) => _PlanItemRow(
                      key: ValueKey('workspace-row-${items[index].id}'),
                      item: items[index],
                      onRename: (title) => controller.editItem(
                        items[index],
                        title,
                        items[index].note,
                      ),
                      linkedEvent: controller.linkedEventFor(items[index].id),
                      promotedNode: controller.promotedNodeFor(items[index]),
                      canPromote: controller.canPromote(items[index]),
                      index: index,
                      count: items.length,
                      editable: plan!.isCurrent,
                      canWithdraw: controller.canWithdraw(items[index]),
                      onMove: (target) => _guard(
                        context,
                        () => controller.moveItem(items[index], target),
                      ),
                      onAction: (action) =>
                          _itemAction(context, items[index], action),
                    ),
                  ),
                  if (canAdd)
                    _PlanQuickAdd(
                      key: const ValueKey('plan-quick-add'),
                      autofocus: openAddItemOnLaunch || items.isEmpty,
                      onSubmit: (title, note, status) async {
                        if (plan == null) {
                          await controller.createFirstStep(
                            node,
                            title,
                            note,
                            status,
                          );
                        } else {
                          await controller.addItem(
                            plan,
                            title,
                            note,
                            initialStatus: status,
                          );
                        }
                      },
                    ),
                  if (plan != null) ...[
                    const _WorkspaceDivider(),
                    Row(
                      children: [
                        Text(
                          '复盘',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(color: HomePilot.textSecondary),
                        ),
                        const Spacer(),
                        IconButton(
                          key: const ValueKey('add-review-note'),
                          onPressed: () => _editReviewNote(context, plan: plan),
                          icon: const Icon(Icons.add, size: 20),
                          tooltip: '添加复盘',
                        ),
                      ],
                    ),
                    if (reviews.isNotEmpty)
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: Text(
                          '上次记录：${reviews.first.content}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        subtitle: Text(
                          '查看全部 ${reviews.length} 条',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        children: reviews
                            .map(
                              (note) => _ReviewNoteRow(
                                note: note,
                                onEdit: () =>
                                    _editReviewNote(context, note: note),
                                onDelete: () =>
                                    _deleteReviewNote(context, note),
                              ),
                            )
                            .toList(),
                      ),
                  ],
                  if (history.isNotEmpty)
                    ExpansionTile(
                      title: const Text('查看历史计划'),
                      children: [
                        for (final past in history)
                          ListTile(
                            title: Text(past.displayTitle),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => PlanDetailPage(
                                  controller: controller,
                                  planId: past.id,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
  Future<void> _renamePlan(BuildContext context, Plan plan) async {
    final value = await _textDialog(
      context,
      title: '修改计划名称',
      initialTitle: plan.title ?? '',
    );
    if (value == null || !context.mounted) return;
    await _guard(context, () => controller.renamePlan(plan, value));
  }

  Future<void> _endPlan(
    BuildContext context,
    Plan plan,
    List<PlanItem> items,
  ) async {
    final unfinished = items.any(
      (item) => item.isExecutable || item.status == PlanItemStatus.dispatched,
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        constraints: DesktopPolish.dialog(
          context,
          DesktopDialogSize.confirmation,
        ),
        title: const Text('结束本轮计划？'),
        content: Text(
          unfinished
              ? '本轮仍有未完成计划项。结束后它们会保留在历史中，但不再参与后续推荐。'
              : '计划项已全部处理，是否结束本轮？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('结束本轮'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await _guard(
      context,
      () => controller.setPlanStatus(plan, PlanStatus.ended),
    );
    if (context.mounted) Navigator.pop(context);
  }

  Future<void> _deletePlan(BuildContext context, Plan plan) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        constraints: DesktopPolish.dialog(
          context,
          DesktopDialogSize.confirmation,
        ),
        title: const Text('删除整个计划？'),
        content: const Text('未进入执行的计划项和复盘会一并删除。世界节点会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('confirm-delete-plan'),
            style: PlanningTheme.destructive,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除计划'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await _guard(context, () => controller.deletePlan(plan));
    if (context.mounted) Navigator.pop(context);
  }

  Future<void> _itemAction(
    BuildContext context,
    PlanItem item,
    String action,
  ) async {
    if (action == 'open-promoted') {
      final node = controller.promotedNodeFor(item);
      if (node == null) {
        _showError(context, const DomainFailure('引用的世界节点已不存在，请刷新'));
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) =>
              PlanDetailPage(controller: controller, worldNodeId: node.id),
        ),
      );
      await controller.load();
      return;
    }
    if (action == 'promote') {
      final plan = controller.plans
          .where((p) => p.id == item.planId)
          .firstOrNull;
      final parent = controller.nodeFor(plan?.worldNodeId ?? '');
      if (parent == null) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          constraints: DesktopPolish.dialog(
            context,
            DesktopDialogSize.confirmation,
          ),
          title: const Text('提升为世界节点？'),
          content: Text(
            '“${item.title}”将成为“${parent.name}”的子世界节点。\n原计划中会保留一个指向该节点的引用。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              key: const ValueKey('confirm-promote-plan-item'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('提升'),
            ),
          ],
        ),
      );
      if (confirmed == true && context.mounted) {
        await _guard(context, () async {
          await controller.promoteItem(item);
        });
      }
      return;
    }
    if (action == 'edit') return _editItem(context, item: item);
    if (action == 'withdraw') {
      return _guard(context, () => controller.withdrawToPlan(item.id));
    }
    if (action == 'drop') {
      return _guard(
        context,
        () => controller.setItemStatus(item, PlanItemStatus.dropped),
      );
    }
    if (action == 'restore') {
      return _guard(
        context,
        () => controller.setItemStatus(item, PlanItemStatus.next),
      );
    }
    if (action == 'delete') {
      return _guard(context, () => controller.deleteItem(item));
    }
  }

  Future<void> _editItem(BuildContext context, {required PlanItem item}) async {
    final result = await _itemDialog(context, item);
    if (result == null || !context.mounted) return;
    await _guard(
      context,
      () => controller.editItem(item, result.$1, result.$2),
    );
  }

  Future<void> _editReviewNote(
    BuildContext context, {
    Plan? plan,
    PlanReviewNote? note,
  }) async {
    final content = await _reviewNoteDialog(context, note);
    if (content == null || !context.mounted) return;
    await _guard(
      context,
      () => note == null
          ? controller.addReviewNote(plan!, content)
          : controller.editReviewNote(note, content),
    );
  }

  Future<void> _deleteReviewNote(
    BuildContext context,
    PlanReviewNote note,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        constraints: DesktopPolish.dialog(
          context,
          DesktopDialogSize.confirmation,
        ),
        title: const Text('删除这条复盘？'),
        content: const Text('删除后会在同步中保留删除记录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('confirm-delete-review-note'),
            style: PlanningTheme.destructive,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await _guard(context, () => controller.deleteReviewNote(note));
    }
  }
}

List<String> _workspacePath(PlanningController controller, WorldNode node) {
  final names = <String>[];
  final seen = <String>{};
  WorldNode? cursor = node;
  while (cursor != null && seen.add(cursor.id)) {
    names.insert(0, cursor.name);
    if (cursor.parentWorldNodeId == null) {
      names.insert(
        0,
        controller.categories
                .where((c) => c.id == cursor!.categoryId)
                .firstOrNull
                ?.name ??
            '未分类',
      );
    }
    cursor = controller.nodeFor(cursor.parentWorldNodeId ?? '');
  }
  return names;
}

class _WorkspaceDivider extends StatelessWidget {
  const _WorkspaceDivider();
  @override
  Widget build(BuildContext context) =>
      Divider(height: 25, thickness: 1, color: HomePilot.hairline);
}

/// One editor for World, Overview and Home refinement. Unsubmitted text is local.
class _PlanQuickAdd extends StatefulWidget {
  const _PlanQuickAdd({
    required this.onSubmit,
    required this.autofocus,
    super.key,
  });
  final Future<void> Function(String, String?, PlanItemStatus) onSubmit;
  final bool autofocus;
  @override
  State<_PlanQuickAdd> createState() => _PlanQuickAddState();
}

class _PlanQuickAddState extends State<_PlanQuickAdd>
    with WidgetsBindingObserver {
  final _title = TextEditingController();

  final _focus = FocusNode();
  bool _busy = false;
  bool _active = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _active = widget.autofocus;
    _focus.addListener(() {
      if (_focus.hasFocus && !_active) setState(() => _active = true);
    });
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focus.requestFocus();
          _reveal();
        }
      });
    }
  }

  void _reveal() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && _focus.hasFocus) {
      Scrollable.ensureVisible(
        context,
        alignment: 1,
        duration: const Duration(milliseconds: 150),
      );
    }
  });
  @override
  void didChangeMetrics() => _reveal();
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _title.dispose();

    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = '写下一步再添加');
      _focus.requestFocus();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(title, null, PlanItemStatus.next);
      if (!mounted) return;
      _title.clear();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _focus.requestFocus();
        _reveal();
      }
    }
  }

  void _cancel() {
    if (_busy) return;
    _title.clear();
    _focus.unfocus();
    setState(() {
      _active = false;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: _InlineTitleEditor(
      fieldKey: const ValueKey('plan-item-title'),
      actionKey: const ValueKey('add-plan-item'),
      controller: _title,
      focusNode: _focus,
      busy: _busy,
      active: _active,
      hint: '添加一步……',
      prefix: const Icon(Icons.add),
      error: _error,
      actionLabel: '添加',
      onSubmit: _submit,
      onCancel: _cancel,
      onOutside: () {
        if (!mounted || _busy) return;
        if (_title.text.trim().isEmpty) {
          _cancel();
        } else {
          _focus.unfocus();
        }
      },
      onTap: () {
        setState(() => _active = true);
        _reveal();
      },
    ),
  );
}

class _InlineTitleEditor extends StatelessWidget {
  const _InlineTitleEditor({
    required this.fieldKey,
    required this.actionKey,
    required this.controller,
    required this.focusNode,
    required this.busy,
    required this.active,
    required this.actionLabel,
    required this.onSubmit,
    required this.onCancel,
    this.cancelKey,
    this.hint,
    this.prefix,
    this.error,
    this.onTap,
    this.onOutside,
  });
  final Key fieldKey, actionKey;
  final Key? cancelKey;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool busy, active;
  final String actionLabel;
  final String? hint, error;
  final Widget? prefix;
  final VoidCallback onSubmit, onCancel;
  final VoidCallback? onTap, onOutside;
  @override
  Widget build(BuildContext context) => TextFieldTapRegion(
    child: Focus(
      onFocusChange: (hasFocus) {
        if (!hasFocus && !busy) onOutside?.call();
      },
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape &&
            !busy) {
          onCancel();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: fieldKey,
            controller: controller,
            focusNode: focusNode,
            readOnly: busy,
            minLines: 1,
            maxLines: null,
            style: Theme.of(context).textTheme.titleMedium,
            textInputAction: TextInputAction.done,
            scrollPadding: const EdgeInsets.all(64),
            onEditingComplete: () {},
            onSubmitted: (_) => onSubmit(),
            onTap: onTap,
            onTapOutside: (_) => onOutside?.call(),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              hintText: hint,
              prefixIcon: prefix,
              errorText: error,
              border: InputBorder.none,
              enabledBorder: active
                  ? PlanningTheme.border(HomePilot.hairlineStrong)
                  : InputBorder.none,
              focusedBorder: PlanningTheme.border(HomePilot.accent, 2),
              disabledBorder: InputBorder.none,
              errorBorder: PlanningTheme.border(PlanningTheme.error),
              focusedErrorBorder: PlanningTheme.border(PlanningTheme.error, 2),
            ),
          ),
          if (active)
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    key: cancelKey,
                    onPressed: busy ? null : onCancel,
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant,
                    ),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    key: actionKey,
                    onPressed: busy ? null : onSubmit,
                    child: Text(actionLabel),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

class _ReviewNoteRow extends StatelessWidget {
  const _ReviewNoteRow({
    required this.note,
    required this.onEdit,
    required this.onDelete,
  });

  final PlanReviewNote note;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Column(
    key: ValueKey('review-note-${note.id}'),
    children: [
      ListTile(
        contentPadding: EdgeInsets.zero,
        minVerticalPadding: 0,
        horizontalTitleGap: 12,
        title: Text(
          note.content,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        subtitle: Text(
          note.updatedAt == note.createdAt
              ? _dateTimeText(note.createdAt)
              : '${_dateTimeText(note.createdAt)} · 已编辑',
        ),
        trailing: PopupMenuButton<String>(
          tooltip: '更多操作',
          icon: const Icon(Icons.more_horiz, size: 18),
          style: HomePilot.buttonStyle(),
          key: ValueKey('review-note-more-${note.id}'),
          onSelected: (value) => value == 'edit' ? onEdit() : onDelete(),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('编辑')),
            PopupMenuItem(
              value: 'delete',
              child: Text('删除', style: TextStyle(color: PlanningTheme.error)),
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
    ],
  );
}

class _PlanItemRow extends StatelessWidget {
  const _PlanItemRow({
    super.key,
    required this.onRename,
    required this.item,
    required this.linkedEvent,
    required this.promotedNode,
    required this.canPromote,
    required this.index,
    required this.count,
    required this.editable,
    required this.canWithdraw,
    required this.onMove,
    required this.onAction,
  });
  final PlanItem item;
  final Future<void> Function(String title) onRename;
  final JaxEvent? linkedEvent;
  final WorldNode? promotedNode;
  final bool canPromote;
  final int index;
  final int count;
  final bool editable;
  final bool canWithdraw;
  final ValueChanged<int> onMove;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    if (item.isPromoted) {
      return PlanningRowSurface(
        onTap: () => onAction('open-promoted'),
        child: ListTile(
          key: ValueKey('plan-reference-${item.id}'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.open_in_new, size: 18),
          title: Text(promotedNode?.name ?? item.title),
          subtitle: Text(
            [
              if (promotedNode == null)
                '引用目标不可用'
              else if (promotedNode!.status == WorldNodeStatus.completed)
                '世界节点 · 已完成'
              else
                '世界节点',
              if (item.note != null) item.note!,
            ].join(' · '),
          ),
        ),
      );
    }
    final mutable = item.isExecutable;
    final dropped = item.status == PlanItemStatus.dropped;
    return PlanningRowSurface(
      child: ListTile(
        key: ValueKey('plan-item-${item.id}'),
        contentPadding: EdgeInsets.zero,
        minVerticalPadding: 0,
        horizontalTitleGap: 12,
        leading: Icon(
          mutable ? Icons.short_text : _itemIcon(item.status),
          size: 16,
          color: dropped ? HomePilot.textMuted : HomePilot.textSecondary,
        ),
        title: _DraftInlineContent(
          item: item,
          enabled: editable && mutable,
          subtitle: _itemSubtitle(item, linkedEvent),
          onSave: onRename,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if ((editable && (mutable || dropped)) || canWithdraw)
              PopupMenuButton<String>(
                tooltip: '更多操作',
                icon: const Icon(Icons.more_horiz, size: 18),
                style: HomePilot.buttonStyle(),
                key: ValueKey('plan-item-more-${item.id}'),
                onSelected: (value) {
                  if (value == 'move-up') {
                    onMove(index - 1);
                  } else if (value == 'move-down') {
                    onMove(index + 1);
                  } else {
                    onAction(value);
                  }
                },
                itemBuilder: (_) => [
                  if (canPromote)
                    const PopupMenuItem(
                      value: 'promote',
                      child: Text('提升为世界节点'),
                    ),
                  if (canWithdraw)
                    const PopupMenuItem(
                      value: 'withdraw',
                      child: Text('收回到计划'),
                    ),
                  if (mutable && index > 0)
                    const PopupMenuItem(value: 'move-up', child: Text('上移')),
                  if (mutable && index < count - 1)
                    const PopupMenuItem(value: 'move-down', child: Text('下移')),
                  if (mutable)
                    const PopupMenuItem(value: 'edit', child: Text('编辑详情')),
                  if (mutable)
                    const PopupMenuItem(
                      value: 'drop',
                      child: Text(
                        '不再需要',
                        style: TextStyle(color: PlanningTheme.error),
                      ),
                    ),
                  if (mutable)
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text(
                        '删除',
                        style: TextStyle(color: PlanningTheme.error),
                      ),
                    ),
                  if (dropped)
                    const PopupMenuItem(
                      value: 'restore',
                      child: Text('恢复计划步骤'),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _DraftInlineContent extends StatefulWidget {
  const _DraftInlineContent({
    required this.item,
    required this.enabled,
    required this.subtitle,
    required this.onSave,
  });
  final PlanItem item;
  final bool enabled;
  final String subtitle;
  final Future<void> Function(String) onSave;
  @override
  State<_DraftInlineContent> createState() => _DraftInlineContentState();
}

class _DraftInlineContentState extends State<_DraftInlineContent> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  bool _editing = false, _saving = false;
  String? _error;

  @override
  void didUpdateWidget(covariant _DraftInlineContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id || !widget.enabled) {
      _editing = false;
      _error = null;
      _focus.unfocus();
    }
  }

  void _begin() {
    if (!widget.enabled || _saving) return;
    _text.value = TextEditingValue(
      text: widget.item.title,
      selection: TextSelection.collapsed(offset: widget.item.title.length),
    );
    setState(() {
      _editing = true;
      _error = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editing) _focus.requestFocus();
    });
  }

  void _finish() {
    setState(() {
      _editing = false;
      _error = null;
    });
    _focus.unfocus();
  }

  Future<void> _save() async {
    if (!mounted || !_editing || _saving) return;
    final title = _text.text.trim();
    if (title.isEmpty || title == widget.item.title) {
      _finish();
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(title);
      if (mounted) _finish();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_editing) {
      return _InlineTitleEditor(
        fieldKey: ValueKey('draft-title-${widget.item.id}'),
        actionKey: ValueKey('save-draft-${widget.item.id}'),
        cancelKey: ValueKey('cancel-draft-${widget.item.id}'),
        controller: _text,
        focusNode: _focus,
        busy: _saving,
        active: true,
        error: _error,
        actionLabel: '保存',
        onSubmit: _save,
        onCancel: _finish,
        onOutside: _save,
      );
    }
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.item.title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: widget.item.status == PlanItemStatus.dropped
                ? HomePilot.textMuted
                : widget.item.status == PlanItemStatus.done
                ? HomePilot.textSecondary
                : HomePilot.textPrimary,
          ),
        ),
        if (widget.subtitle.isNotEmpty)
          Text(
            widget.subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
    return widget.enabled
        ? PlanningRowSurface(
            key: ValueKey('draft-edit-${widget.item.id}'),
            onTap: _begin,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 24),
                child: content,
              ),
            ),
          )
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: content,
          );
  }
}

String _itemSubtitle(PlanItem item, JaxEvent? event) {
  final parts = <String>[];
  if (event != null) {
    parts.add(
      item.status == PlanItemStatus.done
          ? '已完成'
          : '已派发 · ${planningEventStatusText(event.status)}',
    );
  } else {
    final label = _itemStatusText(item.status);
    if (label.isNotEmpty) parts.add(label);
  }
  if (item.note != null) parts.add(item.note!);
  return parts.join('  ·  ');
}

Future<String?> _textDialog(
  BuildContext context, {
  required String title,
  String initialTitle = '',
}) async {
  final controller = TextEditingController(text: initialTitle);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      constraints: DesktopPolish.dialog(context, DesktopDialogSize.form),
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: '名称（可选）'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('保存'),
        ),
      ],
    ),
  );
  return result;
}

Future<(String, String?, PlanItemStatus)?> _itemDialog(
  BuildContext context,
  PlanItem item, {
  String? dialogTitle,
  String? contextLabel,
}) async {
  final title = TextEditingController(text: item.title);
  final note = TextEditingController(text: item.note ?? '');
  final status = item.status;
  final result = await showDialog<(String, String?, PlanItemStatus)>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        constraints: DesktopPolish.dialog(context, DesktopDialogSize.form),
        title: Text(dialogTitle ?? '编辑计划步骤'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (contextLabel != null) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      contextLabel,
                      key: const ValueKey('plan-item-context'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  key: const ValueKey('plan-item-title'),
                  controller: title,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: '步骤'),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('plan-item-note'),
                  controller: note,
                  decoration: const InputDecoration(labelText: '说明（可选）'),
                  minLines: 2,
                  maxLines: 4,
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
          FilledButton(
            onPressed: () {
              if (title.text.trim().isEmpty) return;
              Navigator.pop(context, (
                title.text,
                note.text.trim().isEmpty ? null : note.text,
                status,
              ));
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
  return result;
}

Future<String?> _reviewNoteDialog(
  BuildContext context,
  PlanReviewNote? note,
) async {
  var content = note?.content ?? '';
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      constraints: DesktopPolish.dialog(context, DesktopDialogSize.form),
      title: Text(note == null ? '添加复盘' : '编辑复盘'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: TextFormField(
            key: const ValueKey('review-note-content'),
            initialValue: content,
            autofocus: true,
            minLines: 4,
            maxLines: 10,
            keyboardType: TextInputType.multiline,
            onChanged: (value) => content = value,
            decoration: const InputDecoration(
              labelText: '记录这轮计划的观察与思考',
              alignLabelWithHint: true,
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey('save-review-note'),
          onPressed: () {
            if (content.trim().isEmpty) return;
            Navigator.pop(context, content.trim());
          },
          child: const Text('保存'),
        ),
      ],
    ),
  );
  return result;
}

Future<void> _guard(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (error) {
    if (context.mounted) _showError(context, error);
  }
}

void _showError(BuildContext context, Object error) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(error.toString())));

String _dateText(DateTime value) {
  final local = value.toLocal();
  return '${local.year}-${_two(local.month)}-${_two(local.day)}';
}

String _dateTimeText(DateTime value) {
  final local = value.toLocal();
  return '${_dateText(value)} ${_two(local.hour)}:${_two(local.minute)}';
}

String _two(int value) => value.toString().padLeft(2, '0');

String _itemStatusText(PlanItemStatus status) => switch (status) {
  PlanItemStatus.draft => '',
  PlanItemStatus.next => '',
  PlanItemStatus.dispatched => '已派发',
  PlanItemStatus.done => '已完成',
  PlanItemStatus.dropped => '不再需要',
};

IconData _itemIcon(PlanItemStatus status) => switch (status) {
  PlanItemStatus.draft => Icons.fiber_manual_record,
  PlanItemStatus.next => Icons.arrow_forward,
  PlanItemStatus.dispatched => Icons.call_made,
  PlanItemStatus.done => Icons.check,
  PlanItemStatus.dropped => Icons.remove,
};
