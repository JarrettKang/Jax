import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/entities/plan.dart';
import '../../core/entities/plan_item.dart';
import '../../core/entities/plan_review_note.dart';
import '../../core/entities/jax_event.dart';
import '../../core/entities/world_node.dart';
import '../../core/errors/domain_failure.dart';
import '../controllers/planning_controller.dart';
import '../widgets/world_node_tree_picker.dart';

class PlanningPage extends StatefulWidget {
  const PlanningPage({
    required this.controller,
    this.onAddEventToToday,
    this.isEventToday,
    this.openRequest,
    this.onOpenRequestConsumed,
    super.key,
  });
  final PlanningController controller;
  final Future<String?> Function(String eventId)? onAddEventToToday;
  final bool Function(String eventId)? isEventToday;
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
  Widget build(BuildContext context) => AnimatedBuilder(
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
        body: ListView(
          key: const ValueKey('planning-overview'),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 88),
          children: [
            Row(
              children: [
                Text('规划', style: Theme.of(context).textTheme.headlineSmall),
                const Spacer(),
                FilledButton.tonalIcon(
                  key: const ValueKey('add-plan'),
                  onPressed: () => _createPlan(context),
                  icon: const Icon(Icons.add),
                  label: const Text('添加计划'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (workspaces.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
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
                  onCreate: () => _openWorkspace(workspace.node),
                ),
              ),
          ],
        ),
      );
    },
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
        builder: (_) => PlanDetailPage(
          controller: widget.controller,
          worldNodeId: node.id,
          onAddEventToToday: widget.onAddEventToToday,
          isEventToday: widget.isEventToday,
        ),
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
          onAddEventToToday: widget.onAddEventToToday,
          isEventToday: widget.isEventToday,
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
    required this.onOpen,
    required this.onCreate,
  });
  final FocusedWorldNodePlanning workspace;
  final VoidCallback? onOpen;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final plan = workspace.currentPlan;
    int count(PlanItemStatus status) =>
        workspace.items.where((item) => item.status == status).length;
    final contextText = [
      workspace.category?.name ?? '未分类',
      if (plan == null) '暂无当前计划' else plan.displayTitle,
    ].join(' · ');
    return ListTile(
      key: ValueKey('focused-world-node-${workspace.node.id}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      leading: const Icon(Icons.visibility_outlined),
      title: Text(workspace.node.name),
      subtitle: Text(
        plan == null
            ? workspace.latestEndedPlan == null
                  ? contextText
                  : '$contextText · 上一轮已结束'
            : '$contextText\n${count(PlanItemStatus.next)} 个下一步 · '
                  '${count(PlanItemStatus.dispatched)} 个已派发 · '
                  '${count(PlanItemStatus.done)} 个已完成'
                  '${workspace.items.where((i) => i.status == PlanItemStatus.next).isEmpty ? '' : '\n下一步：${workspace.items.where((i) => i.status == PlanItemStatus.next).take(2).map((i) => i.title).join(' · ')}'}',
      ),
      isThreeLine: plan != null,
      trailing: plan == null
          ? TextButton(
              key: ValueKey('add-plan-for-${workspace.node.id}'),
              onPressed: onCreate,
              child: const Text('开始规划'),
            )
          : const Icon(Icons.chevron_right),
      onTap: onOpen,
    );
  }
}

class _WorldNodeSelector extends StatelessWidget {
  const _WorldNodeSelector({required this.controller});
  final PlanningController controller;

  @override
  Widget build(BuildContext context) => AlertDialog(
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
    this.onAddEventToToday,
    this.isEventToday,
    super.key,
  });
  final PlanningController controller;
  final String? planId;
  final String? worldNodeId;
  final bool openAddItemOnLaunch;
  final Future<String?> Function(String eventId)? onAddEventToToday;
  final bool Function(String eventId)? isEventToday;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
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
      final items = plan == null ? <PlanItem>[] : controller.itemsFor(plan.id);
      final reviews = plan == null
          ? <PlanReviewNote>[]
          : controller.reviewNotesFor(plan.id);
      final canBegin = node.status == WorldNodeStatus.inProgress;
      final canAdd = plan?.isCurrent ?? (history.isEmpty && canBegin);
      return Scaffold(
        appBar: AppBar(
          toolbarHeight: _workspaceTitleHeight(context, node.name),
          title: Text(node.name, softWrap: true),
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
                key: const ValueKey('plan-more'),
                onSelected: (v) {
                  if (v == 'rename') _renamePlan(context, plan);
                  if (v == 'end') _endPlan(context, plan, items);
                  if (v == 'delete') _deletePlan(context, plan);
                },
                itemBuilder: (_) => [
                  if (plan.isCurrent)
                    const PopupMenuItem(value: 'rename', child: Text('修改计划名称')),
                  if (plan.isCurrent)
                    const PopupMenuItem(value: 'end', child: Text('本轮计划结束')),
                  if (controller.canDeletePlan(plan))
                    const PopupMenuItem(value: 'delete', child: Text('删除整个计划')),
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
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                _WorldContext(names: _workspacePath(controller, node)),
                const _WorkspaceDivider(),
                Text('计划步骤', style: Theme.of(context).textTheme.titleSmall),
                if (plan == null && history.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
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
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      plan == null
                          ? '你准备怎么推进它？\n写下第一步就好，不需要一次想完整。'
                          : '这一轮还没有步骤。\n先写下第一件事，之后随时可以补充、调整或删除。',
                    ),
                  ),
                const SizedBox(height: 12),
                const SizedBox(height: 4),
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
                    index: index,
                    count: items.length,
                    editable: plan!.isCurrent,
                    canDispatch: controller.canDispatch(items[index]),
                    canWithdraw: controller.canWithdraw(items[index]),
                    onToggle: () => _guard(
                      context,
                      () => controller.setItemStatus(
                        items[index],
                        items[index].status == PlanItemStatus.next
                            ? PlanItemStatus.draft
                            : PlanItemStatus.next,
                      ),
                    ),
                    onMove: (target) => _guard(
                      context,
                      () => controller.moveItem(items[index], target),
                    ),
                    onAction: (action) =>
                        _itemAction(context, items[index], action),
                    onAddToToday: onAddEventToToday == null
                        ? null
                        : () => _guard(context, () async {
                            final event = controller.linkedEventFor(
                              items[index].id,
                            );
                            if (event == null) {
                              throw const DomainFailure('找不到已派发事项');
                            }
                            final error = await onAddEventToToday!(event.id);
                            if (error != null) throw DomainFailure(error);
                            await controller.load();
                          }),
                    isEventToday: isEventToday,
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
                      Text('复盘', style: Theme.of(context).textTheme.bodySmall),
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
                              onDelete: () => _deleteReviewNote(context, note),
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
                                onAddEventToToday: onAddEventToToday,
                                isEventToday: isEventToday,
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
      (item) =>
          item.status == PlanItemStatus.draft ||
          item.status == PlanItemStatus.next ||
          item.status == PlanItemStatus.dispatched,
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
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
      builder: (_) => AlertDialog(
        title: const Text('删除整个计划？'),
        content: const Text('未进入执行的计划项和复盘会一并删除。世界节点会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('confirm-delete-plan'),
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
    if (action == 'edit') return _editItem(context, item: item);
    if (action == 'dispatch') {
      return _guard(
        context,
        () => controller.dispatchRecommendations([item.id]),
      );
    }
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
        () => controller.setItemStatus(item, PlanItemStatus.draft),
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
      builder: (_) => AlertDialog(
        title: const Text('删除这条复盘？'),
        content: const Text('删除后会在同步中保留删除记录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('confirm-delete-review-note'),
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

double _workspaceTitleHeight(BuildContext context, String title) {
  final painter =
      TextPainter(
        text: TextSpan(
          text: title,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(
        maxWidth: (MediaQuery.sizeOf(context).width - 200).clamp(100.0, 1000.0),
      );
  final height = (painter.height + 16).clamp(kToolbarHeight, double.infinity);
  painter.dispose();
  return height;
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
  Widget build(BuildContext context) => Divider(
    height: 24,
    thickness: .5,
    color: Theme.of(context).colorScheme.outlineVariant,
  );
}

class _WorldContext extends StatelessWidget {
  const _WorldContext({required this.names});
  final List<String> names;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final step = names.length < 2
          ? 0.0
          : (constraints.maxWidth * .22 / (names.length - 1)).clamp(0.0, 12.0);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < names.length; index++)
            Padding(
              padding: EdgeInsets.only(left: index * step, bottom: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (index > 0)
                    const Text('└ ', style: TextStyle(color: Colors.grey)),
                  Expanded(
                    child: Text(
                      names[index],
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: index == names.length - 1
                            ? FontWeight.w500
                            : FontWeight.normal,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    },
  );
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
      await widget.onSubmit(title, null, PlanItemStatus.draft);
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
            textInputAction: TextInputAction.done,
            scrollPadding: const EdgeInsets.all(64),
            onEditingComplete: () {},
            onSubmitted: (_) => onSubmit(),
            onTap: onTap,
            onTapOutside: (_) => onOutside?.call(),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              hintText: hint,
              prefixIcon: prefix,
              errorText: error,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
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
                  TextButton(
                    key: actionKey,
                    onPressed: busy ? null : onSubmit,
                    style: TextButton.styleFrom(
                      textStyle: const TextStyle(fontWeight: FontWeight.w600),
                    ),
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
        dense: true,
        visualDensity: const VisualDensity(vertical: -2),
        minVerticalPadding: 2,
        horizontalTitleGap: 4,
        title: Text(note.content),
        subtitle: Text(
          note.updatedAt == note.createdAt
              ? _dateTimeText(note.createdAt)
              : '${_dateTimeText(note.createdAt)} · 已编辑',
        ),
        trailing: PopupMenuButton<String>(
          key: ValueKey('review-note-more-${note.id}'),
          onSelected: (value) => value == 'edit' ? onEdit() : onDelete(),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('编辑')),
            PopupMenuItem(value: 'delete', child: Text('删除')),
          ],
        ),
      ),
      const Divider(height: 1),
    ],
  );
}

class _PlanItemRow extends StatelessWidget {
  const _PlanItemRow({
    super.key,
    required this.onRename,
    required this.item,
    required this.linkedEvent,
    required this.index,
    required this.count,
    required this.editable,
    required this.canDispatch,
    required this.canWithdraw,
    required this.onToggle,
    required this.onMove,
    required this.onAction,
    required this.onAddToToday,
    required this.isEventToday,
  });
  final PlanItem item;
  final Future<void> Function(String title) onRename;
  final JaxEvent? linkedEvent;
  final int index;
  final int count;
  final bool editable;
  final bool canDispatch;
  final bool canWithdraw;
  final VoidCallback onToggle;
  final ValueChanged<int> onMove;
  final ValueChanged<String> onAction;
  final VoidCallback? onAddToToday;
  final bool Function(String eventId)? isEventToday;

  @override
  Widget build(BuildContext context) {
    final mutable =
        item.status == PlanItemStatus.draft ||
        item.status == PlanItemStatus.next;
    final dropped = item.status == PlanItemStatus.dropped;
    return Opacity(
      opacity: dropped ? .55 : 1,
      child: ListTile(
        key: ValueKey('plan-item-${item.id}'),
        contentPadding: EdgeInsets.zero,
        dense: true,
        visualDensity: const VisualDensity(vertical: -2),
        minVerticalPadding: 2,
        horizontalTitleGap: 4,
        leading: IconButton(
          key: ValueKey('toggle-next-${item.id}'),
          tooltip: item.status == PlanItemStatus.next ? '改为草稿' : '设为下一步',
          onPressed: editable && mutable ? onToggle : null,
          icon: Icon(
            _itemIcon(item.status),
            size: item.status == PlanItemStatus.draft ? 7 : 20,
          ),
        ),
        title: _DraftInlineContent(
          item: item,
          enabled: editable && item.status == PlanItemStatus.draft,
          subtitle: _itemSubtitle(item, linkedEvent),
          onSave: onRename,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (item.status == PlanItemStatus.dispatched &&
                linkedEvent != null &&
                isEventToday?.call(linkedEvent!.id) != true &&
                onAddToToday != null)
              IconButton(
                key: ValueKey('add-dispatched-to-today-${item.id}'),
                tooltip: '加入今日',
                onPressed: onAddToToday,
                icon: const Icon(Icons.today_outlined),
              ),
            if ((editable && (mutable || dropped)) || canWithdraw)
              PopupMenuButton<String>(
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
                  if (canDispatch)
                    const PopupMenuItem(value: 'dispatch', child: Text('加入今日')),
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
                    const PopupMenuItem(value: 'drop', child: Text('不再需要')),
                  if (mutable)
                    const PopupMenuItem(value: 'delete', child: Text('删除')),
                  if (dropped)
                    const PopupMenuItem(value: 'restore', child: Text('恢复为草稿')),
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
        Text(widget.item.title),
        Text(
          widget.subtitle,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
    return widget.enabled
        ? InkWell(
            key: ValueKey('draft-edit-${widget.item.id}'),
            onTap: _begin,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: content,
            ),
          )
        : content;
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
    parts.add(_itemStatusText(item.status));
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
  PlanItemStatus.draft => '草稿',
  PlanItemStatus.next => '下一步',
  PlanItemStatus.dispatched => '已派发',
  PlanItemStatus.done => '已完成',
  PlanItemStatus.dropped => '不再需要',
};

IconData _itemIcon(PlanItemStatus status) => switch (status) {
  PlanItemStatus.draft => Icons.fiber_manual_record,
  PlanItemStatus.next => Icons.arrow_forward,
  PlanItemStatus.dispatched => Icons.call_made,
  PlanItemStatus.done => Icons.check_circle_outline,
  PlanItemStatus.dropped => Icons.remove_circle_outline,
};
