import 'package:flutter/material.dart';

import '../../core/entities/jax_event.dart';
import '../controllers/event_controller.dart';
import '../widgets/event_reorder_buttons.dart';
import 'event_hierarchy_dialog.dart';

Future<void> showHistoryDetailDialog(
  BuildContext context, {
  required EventController controller,
  required JaxEvent event,
}) => showDialog<void>(
  context: context,
  builder: (_) => _HistoryDetailDialog(controller: controller, event: event),
);

class _HistoryDetailDialog extends StatefulWidget {
  const _HistoryDetailDialog({required this.controller, required this.event});

  final EventController controller;
  final JaxEvent event;

  @override
  State<_HistoryDetailDialog> createState() => _HistoryDetailDialogState();
}

class _HistoryDetailDialogState extends State<_HistoryDetailDialog> {
  late JaxEvent _event = widget.event;
  late Future<_HistoryDetailData> _data = _load();

  Future<_HistoryDetailData> _load() async {
    final children = await widget.controller.childrenOf(_event.id);
    return _HistoryDetailData(
      direct: await widget.controller.directDuration(_event.id),
      total: await widget.controller.totalDuration(_event.id),
      children: [
        for (final child in children)
          _ChildDuration(
            event: child,
            total: await widget.controller.totalDuration(child.id),
          ),
      ],
    );
  }

  void _open(JaxEvent event) {
    setState(() {
      _event = event;
      _data = _load();
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_event.name, maxLines: 2, overflow: TextOverflow.ellipsis),
    content: SizedBox(
      width: 520,
      child: FutureBuilder<_HistoryDetailData>(
        future: _data,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.requireData;
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '总投入：${data.total.inMinutes} 分钟',
                  key: const ValueKey('history-total-duration'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  '直接执行：${data.direct.inMinutes} 分钟',
                  key: const ValueKey('history-direct-duration'),
                ),
                const Divider(height: 28),
                Text('直接下层', style: Theme.of(context).textTheme.titleSmall),
                if (data.children.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('暂无直接下层事件'),
                  )
                else
                  ...data.children.map(
                    (child) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(child.event.name),
                      subtitle: Text('总投入：${child.total.inMinutes} 分钟'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          EventReorderButtons(
                            controller: widget.controller,
                            eventId: child.event.id,
                            upKey: ValueKey(
                              'move-up-history-child-${child.event.id}',
                            ),
                            downKey: ValueKey(
                              'move-down-history-child-${child.event.id}',
                            ),
                            onReordered: () {
                              setState(() {
                                _data = _load();
                              });
                            },
                          ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                      onTap: () => _open(child.event),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () async {
          await showEventHierarchyDialog(
            context,
            controller: widget.controller,
            event: _event,
          );
          if (!mounted) return;
          setState(() {
            _data = _load();
          });
        },
        child: const Text('调整层级'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
    ],
  );
}

class _HistoryDetailData {
  const _HistoryDetailData({
    required this.direct,
    required this.total,
    required this.children,
  });

  final Duration direct;
  final Duration total;
  final List<_ChildDuration> children;
}

class _ChildDuration {
  const _ChildDuration({required this.event, required this.total});

  final JaxEvent event;
  final Duration total;
}
