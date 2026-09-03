import 'package:flutter/material.dart';

import '../../core/entities/event_status.dart';
import '../../core/entities/plan.dart';
import '../../core/entities/plan_item.dart';
import '../../core/entities/world_node.dart';
import '../controllers/planning_controller.dart';
import 'planning_page.dart';

class WorldNodeDetailPage extends StatelessWidget {
  const WorldNodeDetailPage({
    required this.controller,
    required this.worldNodeId,
    super.key,
  });

  final PlanningController controller;
  final String worldNodeId;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final node = controller.nodeFor(worldNodeId);
      if (node == null) {
        return const Scaffold(body: Center(child: Text('世界节点不存在')));
      }
      final category = controller.categoryForNode(node);
      final path = controller.pathFor(node);
      final current = controller.currentPlanFor(node.id);
      final history = controller.endedPlansFor(node.id);
      final executions = controller.executionHistoryFor(node.id);
      final totalDuration = executions.fold<Duration>(
        Duration.zero,
        (sum, value) => sum + value.directDuration,
      );
      return Scaffold(
        appBar: AppBar(title: Text(node.name)),
        body: ListView(
          key: const ValueKey('world-node-detail'),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            const _SectionTitle('概览'),
            Text(
              [
                category?.name ?? '未分类',
                ...path.map((value) => value.name),
              ].join(' › '),
              key: const ValueKey('world-node-breadcrumb'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(
              node.status == WorldNodeStatus.completed
                  ? '已完成'
                  : node.isFocused
                  ? '进行中 · 关注中'
                  : '进行中',
            ),
            const Divider(height: 32),
            const _SectionTitle('当前计划'),
            if (current == null)
              _EmptyCurrentPlan(
                completed: node.status == WorldNodeStatus.completed,
                onCreate: () => _createPlan(context, node),
              )
            else
              _CurrentPlanSummary(
                plan: current,
                items: controller.itemsFor(current.id),
                onOpen: () => _openPlan(context, current),
              ),
            const Divider(height: 32),
            const _SectionTitle('历史计划'),
            if (history.isEmpty)
              const _QuietEmpty('还没有已结束的计划')
            else
              ...history.map(
                (plan) => ListTile(
                  key: ValueKey('historical-plan-${plan.id}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(plan.displayTitle),
                  subtitle: Text(
                    '第 ${plan.roundNumber} 轮 · ${_date(plan.createdAt)}—${_date(plan.endedAt!)} · '
                    '${controller.itemsFor(plan.id).length} 个计划项 · '
                    '${controller.reviewNotesFor(plan.id).length} 条复盘',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openPlan(context, plan),
                ),
              ),
            const Divider(height: 32),
            Row(
              children: [
                const Expanded(child: _SectionTitle('执行历史')),
                if (executions.isNotEmpty)
                  Text(
                    '直接用时 ${_duration(totalDuration)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
            if (executions.isEmpty)
              const _QuietEmpty('还没有由此节点计划派发的执行记录')
            else
              ...executions.map(
                (entry) => ListTile(
                  key: ValueKey('world-execution-${entry.event.id}'),
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(_eventIcon(entry.event.status)),
                  title: Text(entry.event.name),
                  subtitle: Text(
                    '${_eventStatus(entry.event.status)} · ${_dateTime(entry.recentAt)} · '
                    '${_duration(entry.directDuration)} · 第 ${entry.plan.roundNumber} 轮',
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );

  Future<void> _createPlan(BuildContext context, WorldNode node) async {
    try {
      final plan = await controller.createPlan(node);
      if (context.mounted) await _openPlan(context, plan);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _openPlan(BuildContext context, Plan plan) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlanDetailPage(controller: controller, planId: plan.id),
      ),
    );
    await controller.load();
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

class _QuietEmpty extends StatelessWidget {
  const _QuietEmpty(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(text, style: Theme.of(context).textTheme.bodySmall),
  );
}

class _EmptyCurrentPlan extends StatelessWidget {
  const _EmptyCurrentPlan({required this.completed, required this.onCreate});
  final bool completed;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _QuietEmpty(completed ? '节点已完成，可查看历史；恢复节点后才能创建新计划' : '当前没有计划'),
      if (!completed)
        TextButton.icon(
          key: const ValueKey('detail-add-plan'),
          onPressed: onCreate,
          icon: const Icon(Icons.add),
          label: const Text('添加计划'),
        ),
    ],
  );
}

class _CurrentPlanSummary extends StatelessWidget {
  const _CurrentPlanSummary({
    required this.plan,
    required this.items,
    required this.onOpen,
  });
  final Plan plan;
  final List<PlanItem> items;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    int count(PlanItemStatus status) =>
        items.where((item) => item.status == status).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          key: const ValueKey('current-plan-summary'),
          contentPadding: EdgeInsets.zero,
          title: Text(plan.displayTitle),
          subtitle: Text(
            '当前 · 第 ${plan.roundNumber} 轮 · '
            '${count(PlanItemStatus.next)} 下一步 · '
            '${count(PlanItemStatus.dispatched)} 已派发 · '
            '${count(PlanItemStatus.done)} 已完成',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: onOpen,
        ),
        for (final item in items.take(3))
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 4),
            child: Text(
              '• ${item.title}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        if (items.length > 3)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 4),
            child: Text(
              '另有 ${items.length - 3} 项',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

String _date(DateTime value) {
  final local = value.toLocal();
  return '${local.year}-${_two(local.month)}-${_two(local.day)}';
}

String _dateTime(DateTime value) {
  final local = value.toLocal();
  return '${_date(value)} ${_two(local.hour)}:${_two(local.minute)}';
}

String _two(int value) => value.toString().padLeft(2, '0');

String _duration(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60);
  if (hours == 0) return '$minutes 分钟';
  return '$hours 小时 $minutes 分钟';
}

String _eventStatus(EventStatus status) => switch (status) {
  EventStatus.pending => '待开始',
  EventStatus.running => '进行中',
  EventStatus.paused => '暂停',
  EventStatus.waiting => '等待',
  EventStatus.completed => '已完成',
};

IconData _eventIcon(EventStatus status) => switch (status) {
  EventStatus.pending => Icons.radio_button_unchecked,
  EventStatus.running => Icons.play_circle_outline,
  EventStatus.paused => Icons.pause_circle_outline,
  EventStatus.waiting => Icons.hourglass_empty,
  EventStatus.completed => Icons.check_circle_outline,
};
