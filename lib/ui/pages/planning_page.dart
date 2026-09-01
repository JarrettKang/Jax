import 'package:flutter/material.dart';

import '../../core/entities/plan.dart';
import '../../core/entities/plan_item.dart';
import '../../core/entities/world_node.dart';
import '../controllers/planning_controller.dart';

class PlanningPage extends StatefulWidget {
  const PlanningPage({required this.controller, super.key});
  final PlanningController controller;

  @override
  State<PlanningPage> createState() => _PlanningPageState();
}

class _PlanningPageState extends State<PlanningPage> {
  @override
  void initState() {
    super.initState();
    widget.controller.load();
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
      final focused = controller.plans
          .where((plan) => plan.status == PlanStatus.focused)
          .toList();
      final waiting = controller.plans
          .where((plan) => plan.status == PlanStatus.waiting)
          .toList();
      final ended = controller.plans
          .where((plan) => plan.status == PlanStatus.ended)
          .toList();
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
            _PlanSection(
              title: '已关注',
              emptyText: '还没有正在关注的计划',
              plans: focused,
              controller: controller,
              onOpen: _openPlan,
            ),
            if (ended.isNotEmpty) ...[
              const SizedBox(height: 18),
              ExpansionTile(
                key: const ValueKey('ended-plans'),
                tilePadding: EdgeInsets.zero,
                title: Text('历史计划 (${ended.length})'),
                children: [
                  _PlanSection(
                    title: '',
                    emptyText: '',
                    plans: ended,
                    controller: controller,
                    onOpen: _openPlan,
                  ),
                ],
              ),
            ],
            const SizedBox(height: 24),
            _PlanSection(
              title: '等待中',
              emptyText: '没有暂时等待的计划',
              plans: waiting,
              controller: controller,
              onOpen: _openPlan,
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

  Future<void> _openPlan(Plan plan) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            PlanDetailPage(controller: widget.controller, planId: plan.id),
      ),
    );
    await widget.controller.load();
  }
}

class _PlanSection extends StatelessWidget {
  const _PlanSection({
    required this.title,
    required this.emptyText,
    required this.plans,
    required this.controller,
    required this.onOpen,
  });
  final String title;
  final String emptyText;
  final List<Plan> plans;
  final PlanningController controller;
  final ValueChanged<Plan> onOpen;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (title.isNotEmpty) ...[
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
      ],
      if (plans.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(emptyText, style: Theme.of(context).textTheme.bodySmall),
        )
      else
        ...plans.map((plan) {
          final node = controller.nodeFor(plan.worldNodeId);
          final items = controller.itemsFor(plan.id);
          final next = items
              .where((item) => item.status == PlanItemStatus.next)
              .length;
          final category = node == null
              ? null
              : controller.categoryForNode(node);
          return ListTile(
            key: ValueKey('plan-${plan.id}'),
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: Icon(
              plan.status == PlanStatus.focused
                  ? Icons.visibility_outlined
                  : Icons.pause_circle_outline,
              color: category == null
                  ? Theme.of(context).colorScheme.outline
                  : Theme.of(context).colorScheme.primary,
            ),
            title: Text(node?.name ?? '未知世界节点'),
            subtitle: Text(
              '${plan.displayTitle}  ·  $next 个 next  ·  ${items.length} 个计划项',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => onOpen(plan),
          );
        }),
    ],
  );
}

class _WorldNodeSelector extends StatefulWidget {
  const _WorldNodeSelector({required this.controller});
  final PlanningController controller;

  @override
  State<_WorldNodeSelector> createState() => _WorldNodeSelectorState();
}

class _WorldNodeSelectorState extends State<_WorldNodeSelector> {
  final Set<String> _collapsedCategories = {};
  final Set<String> _collapsedBranches = {};

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('选择世界节点'),
    content: SizedBox(
      width: 520,
      height: 540,
      child: widget.controller.worldNodes.isEmpty
          ? const Center(child: Text('暂无世界节点'))
          : ListView(
              key: const ValueKey('planning-world-node-selector'),
              children: [
                for (final category in [
                  ...widget.controller.categories.map(
                    (value) => (id: value.id, name: value.name),
                  ),
                  (id: null, name: '未分类'),
                ])
                  _section(category.id, category.name),
              ],
            ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
    ],
  );

  Widget _section(String? categoryId, String name) {
    final key = categoryId ?? 'unclassified';
    final roots = widget.controller.worldNodes
        .where(
          (node) =>
              node.parentWorldNodeId == null && node.categoryId == categoryId,
        )
        .toList()
      ..sort(_sort);
    final collapsed = _collapsedCategories.contains(key);
    return Column(
      children: [
        ListTile(
          key: ValueKey('planning-selector-category-$key'),
          dense: true,
          leading: Icon(collapsed ? Icons.chevron_right : Icons.expand_more),
          title: Text(name),
          subtitle: Text('${roots.length} 个根节点'),
          onTap: () => setState(() {
            collapsed
                ? _collapsedCategories.remove(key)
                : _collapsedCategories.add(key);
          }),
        ),
        if (!collapsed)
          for (final root in roots) _node(root, 0),
      ],
    );
  }

  Widget _node(WorldNode node, int depth) {
    final children = widget.controller.worldNodes
        .where((value) => value.parentWorldNodeId == node.id)
        .toList()
      ..sort(_sort);
    final collapsed = _collapsedBranches.contains(node.id);
    final completed = node.status == WorldNodeStatus.completed;
    final occupied = widget.controller.hasCurrentPlan(node.id);
    return Column(
      children: [
        ListTile(
          key: ValueKey('select-world-node-${node.id}'),
          contentPadding: EdgeInsets.only(left: 20.0 + depth * 22, right: 8),
          dense: true,
          enabled: !completed && !occupied,
          leading: children.isEmpty
              ? const Icon(Icons.subdirectory_arrow_right)
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
          title: Text(node.name),
          subtitle: completed
              ? const Text('已完成：只能查看历史，不能创建计划')
              : occupied
              ? const Text('已有当前计划：请先查看或结束该轮')
              : null,
          onTap: completed || occupied
              ? null
              : () => Navigator.pop(context, node),
        ),
        if (!collapsed)
          for (final child in children) _node(child, depth + 1),
      ],
    );
  }

  static int _sort(WorldNode a, WorldNode b) {
    final order = a.sortOrder.compareTo(b.sortOrder);
    return order != 0 ? order : a.id.compareTo(b.id);
  }
}

class PlanDetailPage extends StatelessWidget {
  const PlanDetailPage({
    required this.controller,
    required this.planId,
    super.key,
  });
  final PlanningController controller;
  final String planId;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final plan = controller.plans
          .where((value) => value.id == planId)
          .firstOrNull;
      if (plan == null) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final node = controller.nodeFor(plan.worldNodeId);
      final items = controller.itemsFor(plan.id);
      return Scaffold(
        appBar: AppBar(
          title: Text(node?.name ?? '计划'),
          actions: [
            if (plan.isCurrent)
              TextButton.icon(
                key: const ValueKey('toggle-plan-focus'),
                onPressed: () => _guard(
                  context,
                  () => controller.setPlanStatus(
                    plan,
                    plan.status == PlanStatus.focused
                        ? PlanStatus.waiting
                        : PlanStatus.focused,
                  ),
                ),
                icon: Icon(
                  plan.status == PlanStatus.focused
                      ? Icons.pause_circle_outline
                      : Icons.visibility_outlined,
                ),
                label: Text(plan.status == PlanStatus.focused ? '暂时等待' : '关注'),
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
              _planStatusText(plan.status),
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
        content: const Text('未进入执行的计划项会一并删除。世界节点会保留。'),
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
  }) async {
    final result = await _itemDialog(context, item);
    if (result == null || !context.mounted) return;
    if (item == null) {
      await _guard(
        context,
        () => controller.addItem(plan!, result.$1, result.$2),
      );
    } else {
      await _guard(
        context,
        () => controller.editItem(item, result.$1, result.$2),
      );
    }
  }
}

class _PlanItemRow extends StatelessWidget {
  const _PlanItemRow({
    required this.item,
    required this.index,
    required this.count,
    required this.editable,
    required this.onToggle,
    required this.onMove,
    required this.onAction,
  });
  final PlanItem item;
  final int index;
  final int count;
  final bool editable;
  final VoidCallback onToggle;
  final ValueChanged<int> onMove;
  final ValueChanged<String> onAction;

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
        subtitle: item.note == null
            ? Text(_itemStatusText(item.status))
            : Text('${_itemStatusText(item.status)}  ·  ${item.note}'),
        trailing: editable
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

Future<(String, String?)?> _itemDialog(
  BuildContext context,
  PlanItem? item,
) async {
  final title = TextEditingController(text: item?.title ?? '');
  final note = TextEditingController(text: item?.note ?? '');
  final result = await showDialog<(String, String?)>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(item == null ? '添加计划项' : '编辑计划项'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
            ));
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
  PlanStatus.focused => '已关注',
  PlanStatus.waiting => '等待中',
  PlanStatus.ended => '已结束',
};

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
