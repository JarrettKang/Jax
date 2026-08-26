import 'package:flutter/material.dart';

import '../../core/entities/jax_event.dart';
import '../controllers/event_controller.dart';
import '../widgets/event_more_menu_button.dart';
import '../widgets/event_reorder_drag.dart';
import 'event_hierarchy_dialog.dart';
import 'history_detail_dialog.dart';

class HistoryPage extends StatelessWidget {
  const HistoryPage({required this.controller, super.key});
  final EventController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => controller.history.isEmpty
        ? const Center(child: Text('暂无历史记录'))
        : ListView(
            padding: const EdgeInsets.all(12),
            children: controller.historyRoots
                .map(
                  (event) => EventReorderDropTarget(
                    controller: controller,
                    eventId: event.id,
                    child: Card(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final details =
                              '开始：${_time(event.firstStartedAt!.toLocal())}\n结束：${_time(event.completedAt!.toLocal())}\n持续：${controller.elapsedFor(event).inMinutes} 分钟';
                          final actions = <Widget>[
                            IconButton(
                              key: ValueKey('history-detail-${event.id}'),
                              icon: const Icon(Icons.analytics_outlined),
                              tooltip: '投入详情',
                              onPressed: () => showHistoryDetailDialog(
                                context,
                                controller: controller,
                                event: event,
                              ),
                            ),
                            EventMoreMenuButton<_HistoryMenuAction>(
                              key: ValueKey('more-history-${event.id}'),
                              onSelected: (_) =>
                                  _confirmRestore(context, event),
                              itemBuilder: (_) => [
                                PopupMenuItem(
                                  key: ValueKey('restore-history-${event.id}'),
                                  value: _HistoryMenuAction.restore,
                                  child: const ListTile(
                                    leading: Icon(Icons.restore),
                                    title: Text('恢复事件'),
                                  ),
                                ),
                              ],
                            ),
                            IconButton(
                              key: ValueKey('history-hierarchy-${event.id}'),
                              icon: const Icon(Icons.account_tree_outlined),
                              tooltip: '调整层级',
                              onPressed: () => showEventHierarchyDialog(
                                context,
                                controller: controller,
                                event: event,
                              ),
                            ),
                            IconButton(
                              key: ValueKey('delete-history-${event.id}'),
                              icon: const Icon(Icons.delete_outline),
                              tooltip: '删除记录',
                              onPressed: () => _confirmDelete(context, event),
                            ),
                            EventReorderHandle(
                              controller: controller,
                              eventId: event.id,
                            ),
                          ];
                          if (constraints.maxWidth < 600) {
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    event.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(details),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: Wrap(children: actions),
                                  ),
                                ],
                              ),
                            );
                          }
                          return ListTile(
                            title: Text(event.name),
                            subtitle: Text(details),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: actions,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
  );

  Future<void> _confirmDelete(BuildContext context, JaxEvent event) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除历史记录'),
        content: Text('确定删除“${event.name}”的执行记录吗？'),
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
    if (confirmed != true || !context.mounted) return;
    final error = await controller.deleteHistory(event.id);
    if (error != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<void> _confirmRestore(BuildContext context, JaxEvent event) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复事件'),
        content: Text('恢复“${event.name}”后，该事件将重新进入事件列表，原有执行记录会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('恢复事件'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final error = await controller.restore(event.id);
    if (error != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  static String _time(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}

enum _HistoryMenuAction { restore }
