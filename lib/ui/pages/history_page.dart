import 'package:flutter/material.dart';

import '../../core/entities/jax_event.dart';
import '../controllers/event_controller.dart';

class HistoryPage extends StatelessWidget {
  const HistoryPage({required this.controller, super.key});
  final EventController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => controller.history.isEmpty
        ? const Center(child: Text('暂无历史记录'))
        : ListView(
            padding: const EdgeInsets.all(24),
            children: controller.history
                .map(
                  (event) => Card(
                    child: ListTile(
                      title: Text(event.name),
                      subtitle: Text(
                        '开始：${_time(event.firstStartedAt!.toLocal())}\n结束：${_time(event.completedAt!.toLocal())}\n持续：${controller.elapsedFor(event).inMinutes} 分钟',
                      ),
                      trailing: IconButton(
                        key: ValueKey('delete-history-${event.id}'),
                        icon: const Icon(Icons.delete_outline),
                        tooltip: '删除记录',
                        onPressed: () => _confirmDelete(context, event),
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

  static String _time(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}
