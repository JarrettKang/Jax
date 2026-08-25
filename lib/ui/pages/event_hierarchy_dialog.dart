import 'package:flutter/material.dart';

import '../../core/entities/jax_event.dart';
import '../controllers/event_controller.dart';

Future<void> showEventHierarchyDialog(
  BuildContext context, {
  required EventController controller,
  required JaxEvent event,
}) => showDialog<void>(
  context: context,
  builder: (_) => _EventHierarchyDialog(controller: controller, event: event),
);

class _EventHierarchyDialog extends StatefulWidget {
  const _EventHierarchyDialog({required this.controller, required this.event});

  final EventController controller;
  final JaxEvent event;

  @override
  State<_EventHierarchyDialog> createState() => _EventHierarchyDialogState();
}

class _EventHierarchyDialogState extends State<_EventHierarchyDialog> {
  late JaxEvent _event = widget.event;
  late Future<_HierarchyViewData> _data = _load();

  Future<_HierarchyViewData> _load() async => _HierarchyViewData(
    parent: await widget.controller.parentOf(_event.id),
    children: await widget.controller.childrenOf(_event.id),
  );

  void _open(JaxEvent event) {
    setState(() {
      _event = event;
      _data = _load();
    });
  }

  void _refresh() {
    setState(() {
      _data = _load();
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_event.name, maxLines: 2, overflow: TextOverflow.ellipsis),
    content: SizedBox(
      width: 520,
      child: FutureBuilder<_HierarchyViewData>(
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
                Text('上层事件', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                if (data.parent == null)
                  const Text('无（顶级事件）')
                else
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(data.parent!.name),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(data.parent!),
                  ),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: () => _chooseParent(data.parent),
                      child: const Text('设置上层'),
                    ),
                    if (data.parent != null)
                      TextButton(
                        onPressed: () => _setParent(null),
                        child: const Text('解除上层'),
                      ),
                  ],
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
                      title: Text(child.name),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _open(child),
                    ),
                  ),
                OutlinedButton(
                  onPressed: _chooseChild,
                  child: const Text('添加下层'),
                ),
              ],
            ),
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
    ],
  );

  Future<void> _chooseParent(JaxEvent? existingParent) async {
    final candidates = await widget.controller.parentCandidates(_event.id);
    if (!mounted) return;
    final selected = await _choose('选择上层事件', candidates);
    if (selected == null || selected.id == existingParent?.id || !mounted) {
      return;
    }
    if (existingParent != null &&
        !await _confirmMove('将“${_event.name}”移动到“${selected.name}”下吗？')) {
      return;
    }
    await _setParent(selected.id);
  }

  Future<void> _chooseChild() async {
    final candidates = await widget.controller.childCandidates(_event.id);
    if (!mounted) return;
    final selected = await _choose('选择下层事件', candidates);
    if (selected == null || !mounted) return;
    final existingParent = await widget.controller.parentOf(selected.id);
    if (!mounted) return;
    if (existingParent != null && existingParent.id != _event.id) {
      final confirmed = await _confirmMove(
        '将“${selected.name}”从“${existingParent.name}”移动到“${_event.name}”下吗？',
      );
      if (!confirmed) return;
    }
    final error = await widget.controller.setParent(selected.id, _event.id);
    if (!mounted) return;
    _showError(error);
    if (error == null) _refresh();
  }

  Future<JaxEvent?> _choose(String title, List<JaxEvent> candidates) {
    return showDialog<JaxEvent>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(title),
        children: candidates.isEmpty
            ? const [
                Padding(padding: EdgeInsets.all(24), child: Text('没有可选择的事件')),
              ]
            : candidates
                  .map(
                    (candidate) => SimpleDialogOption(
                      key: ValueKey('hierarchy-candidate-${candidate.id}'),
                      onPressed: () => Navigator.pop(context, candidate),
                      child: Text(candidate.name),
                    ),
                  )
                  .toList(),
      ),
    );
  }

  Future<bool> _confirmMove(String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('确认移动'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('移动'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _setParent(String? parentId) async {
    final error = await widget.controller.setParent(_event.id, parentId);
    if (!mounted) return;
    _showError(error);
    if (error == null) {
      final updated = widget.controller.events
          .where((event) => event.id == _event.id)
          .firstOrNull;
      if (updated != null) _event = updated;
      _refresh();
    }
  }

  void _showError(String? error) {
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }
}

class _HierarchyViewData {
  const _HierarchyViewData({required this.parent, required this.children});

  final JaxEvent? parent;
  final List<JaxEvent> children;
}
