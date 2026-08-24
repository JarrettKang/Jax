import 'package:flutter/material.dart';

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
            children: controller.history.map((event) {
              final started = event.firstStartedAt!.toLocal();
              final ended = event.completedAt!.toLocal();
              final duration = controller.elapsedFor(event);
              return Card(
                child: ListTile(
                  title: Text(event.name),
                  subtitle: Text(
                    '开始：${_time(started)}\n结束：${_time(ended)}\n持续：${duration.inMinutes} 分钟',
                  ),
                ),
              );
            }).toList(),
          ),
  );
  static String _time(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}
