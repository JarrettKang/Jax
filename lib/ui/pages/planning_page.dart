import 'package:flutter/material.dart';

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
                  onOpen: workspace.currentPlan == null
                      ? null
                      : () => _openPlan(workspace.currentPlan!),
                  onCreate: () => _createPlanFor(workspace.node),
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

  Future<void> _createPlanFor(WorldNode node) async {
    try {
      final plan = await widget.controller.createPlan(node);
      if (mounted) await _openPlan(plan);
    } catch (error) {
      if (mounted) _showError(context, error);
    }
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
                  '${count(PlanItemStatus.done)} 个已完成',
      ),
      isThreeLine: plan != null,
      trailing: plan == null
          ? TextButton(
              key: ValueKey('add-plan-for-${workspace.node.id}'),
              onPressed: onCreate,
              child: Text(workspace.latestEndedPlan == null ? '添加计划' : '添加新一轮'),
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
    required this.planId,
    this.openAddItemOnLaunch = false,
    this.onAddEventToToday,
    this.isEventToday,
    super.key,
  });
  final PlanningController controller;
  final String planId;
  final bool openAddItemOnLaunch;
  final Future<String?> Function(String eventId)? onAddEventToToday;
  final bool Function(String eventId)? isEventToday;

  @override
  Widget build(BuildContext context) => _InitialPlanItemEditorLauncher(
    enabled: openAddItemOnLaunch,
    onOpen: (editorContext) async {
      final plan = controller.plans
          .where((value) => value.id == planId)
          .firstOrNull;
      if (plan == null) {
        _showError(editorContext, const DomainFailure('目标计划已不存在'));
        return;
      }
      await _editItem(editorContext, plan: plan, quickRefinement: true);
    },
    child: AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final plan = controller.plans
            .where((value) => value.id == planId)
            .firstOrNull;
        if (plan == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final node = controller.nodeFor(plan.worldNodeId);
        final items = controller.itemsFor(plan.id);
        final reviewNotes = controller.reviewNotesFor(plan.id);
        return Scaffold(
          appBar: AppBar(
            title: Text(node?.name ?? '计划'),
            actions: [
              if (plan.isCurrent &&
                  node?.status == WorldNodeStatus.inProgress &&
                  node?.isFocused == false)
                TextButton.icon(
                  key: const ValueKey('focus-world-node-from-plan'),
                  onPressed: () => _guard(
                    context,
                    () => controller.setWorldNodeFocus(node!, true),
                  ),
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('关注节点'),
                ),
              PopupMenuButton<String>(
                key: const ValueKey('plan-more'),
                onSelected: (value) {
                  if (value == 'rename') _renamePlan(context, plan);
                  if (value == 'end') _endPlan(context, plan, items);
                  if (value == 'delete') _deletePlan(context, plan);
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
          body: ListView(
            key: const ValueKey('plan-detail'),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            children: [
              Text(
                plan.displayTitle,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                '${_planStatusText(plan.status)} · 第 ${plan.roundNumber} 轮 · 创建于 ${_dateText(plan.createdAt)}'
                '${plan.endedAt == null ? '' : ' · 结束于 ${_dateText(plan.endedAt!)}'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Divider(height: 28),
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('还没有计划项')),
                )
              else
                ...List.generate(
                  items.length,
                  (index) => _PlanItemRow(
                    item: items[index],
                    linkedEvent: controller.linkedEventFor(items[index].id),
                    index: index,
                    count: items.length,
                    editable: plan.isCurrent,
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
              const Divider(height: 32),
              Row(
                children: [
                  Text('复盘', style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  TextButton.icon(
                    key: const ValueKey('add-review-note'),
                    onPressed: () => _editReviewNote(context, plan: plan),
                    icon: const Icon(Icons.add_comment_outlined),
                    label: const Text('添加复盘'),
                  ),
                ],
              ),
              if (reviewNotes.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    '还没有复盘记录',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                )
              else
                ...reviewNotes.map(
                  (note) => _ReviewNoteRow(
                    note: note,
                    onEdit: () => _editReviewNote(context, note: note),
                    onDelete: () => _deleteReviewNote(context, note),
                  ),
                ),
            ],
          ),
          floatingActionButton: plan.isCurrent
              ? FloatingActionButton.extended(
                  key: const ValueKey('add-plan-item'),
                  onPressed: () => _editItem(context, plan: plan),
                  icon: const Icon(Icons.add),
                  label: const Text('添加步骤'),
                )
              : null,
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

  Future<void> _editItem(
    BuildContext context, {
    Plan? plan,
    PlanItem? item,
    bool quickRefinement = false,
  }) async {
    final targetPlan =
        plan ??
        controller.plans.where((value) => value.id == item?.planId).firstOrNull;
    final node = targetPlan == null
        ? null
        : controller.nodeFor(targetPlan.worldNodeId);
    final result = await _itemDialog(
      context,
      item,
      dialogTitle: quickRefinement ? '补充计划步骤' : null,
      contextLabel: targetPlan == null
          ? null
          : '${node?.name ?? '未知节点'} · ${targetPlan.displayTitle}',
    );
    if (result == null || !context.mounted) return;
    if (item == null) {
      await _guard(
        context,
        () => controller.addItem(
          plan!,
          result.$1,
          result.$2,
          initialStatus: result.$3,
        ),
      );
    } else {
      await _guard(
        context,
        () => controller.editItem(item, result.$1, result.$2),
      );
    }
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

class _InitialPlanItemEditorLauncher extends StatefulWidget {
  const _InitialPlanItemEditorLauncher({
    required this.enabled,
    required this.onOpen,
    required this.child,
  });

  final bool enabled;
  final Future<void> Function(BuildContext context) onOpen;
  final Widget child;

  @override
  State<_InitialPlanItemEditorLauncher> createState() =>
      _InitialPlanItemEditorLauncherState();
}

class _InitialPlanItemEditorLauncherState
    extends State<_InitialPlanItemEditorLauncher> {
  @override
  void initState() {
    super.initState();
    if (widget.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onOpen(context);
      });
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
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
    required this.item,
    required this.linkedEvent,
    required this.index,
    required this.count,
    required this.editable,
    required this.onToggle,
    required this.onMove,
    required this.onAction,
    required this.onAddToToday,
    required this.isEventToday,
  });
  final PlanItem item;
  final JaxEvent? linkedEvent;
  final int index;
  final int count;
  final bool editable;
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
        leading: IconButton(
          key: ValueKey('toggle-next-${item.id}'),
          tooltip: item.status == PlanItemStatus.next ? '改为草稿' : '设为下一步',
          onPressed: editable && mutable ? onToggle : null,
          icon: Icon(
            item.status == PlanItemStatus.next
                ? Icons.adjust
                : _itemIcon(item.status),
          ),
        ),
        title: Text(item.title),
        subtitle: Text(_itemSubtitle(item, linkedEvent)),
        trailing:
            item.status == PlanItemStatus.dispatched &&
                linkedEvent != null &&
                isEventToday?.call(linkedEvent!.id) != true &&
                onAddToToday != null
            ? IconButton(
                key: ValueKey('add-dispatched-to-today-${item.id}'),
                tooltip: '加入今日',
                onPressed: onAddToToday,
                icon: const Icon(Icons.today_outlined),
              )
            : editable
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (mutable && index > 0)
                    IconButton(
                      tooltip: '上移',
                      onPressed: () => onMove(index - 1),
                      icon: const Icon(Icons.arrow_upward, size: 19),
                    ),
                  if (mutable && index < count - 1)
                    IconButton(
                      tooltip: '下移',
                      onPressed: () => onMove(index + 1),
                      icon: const Icon(Icons.arrow_downward, size: 19),
                    ),
                  PopupMenuButton<String>(
                    onSelected: onAction,
                    itemBuilder: (_) => [
                      if (mutable)
                        const PopupMenuItem(value: 'edit', child: Text('编辑详情')),
                      if (mutable)
                        const PopupMenuItem(value: 'drop', child: Text('不再需要')),
                      if (mutable)
                        const PopupMenuItem(value: 'delete', child: Text('删除')),
                      if (dropped)
                        const PopupMenuItem(
                          value: 'restore',
                          child: Text('恢复为草稿'),
                        ),
                    ],
                  ),
                ],
              )
            : null,
      ),
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
  PlanItem? item, {
  String? dialogTitle,
  String? contextLabel,
}) async {
  final title = TextEditingController(text: item?.title ?? '');
  final note = TextEditingController(text: item?.note ?? '');
  var status = item?.status ?? PlanItemStatus.draft;
  final result = await showDialog<(String, String?, PlanItemStatus)>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(dialogTitle ?? (item == null ? '添加计划步骤' : '编辑计划步骤')),
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
                if (item == null) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<PlanItemStatus>(
                    key: const ValueKey('plan-item-initial-status'),
                    initialValue: status,
                    decoration: const InputDecoration(labelText: '初始状态'),
                    items: const [
                      DropdownMenuItem(
                        value: PlanItemStatus.draft,
                        child: Text('草稿'),
                      ),
                      DropdownMenuItem(
                        value: PlanItemStatus.next,
                        child: Text('下一步'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setDialogState(() => status = value);
                    },
                  ),
                ],
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

String _planStatusText(PlanStatus status) => switch (status) {
  PlanStatus.current => '当前',
  PlanStatus.ended => '已结束',
};

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
  PlanItemStatus.draft => Icons.radio_button_unchecked,
  PlanItemStatus.next => Icons.adjust,
  PlanItemStatus.dispatched => Icons.call_made,
  PlanItemStatus.done => Icons.check_circle_outline,
  PlanItemStatus.dropped => Icons.remove_circle_outline,
};
