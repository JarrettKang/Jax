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
    final legalIds = (await widget.controller.parentCandidates(_event.id))
        .map((event) => event.id)
        .toSet();
    if (!mounted) return;
    final selected = await _choose(
      title: '选择上层事件',
      mode: _PickerMode.parent,
      legalIds: legalIds,
      existingParent: existingParent,
    );
    if (selected == null || !mounted) return;
    if (selected.removeParent) {
      if (existingParent != null) await _setParent(null);
      return;
    }
    final event = selected.event!;
    if (event.id == existingParent?.id) return;
    if (existingParent != null &&
        !await _confirmMove('将“${_event.name}”移动到“${event.name}”下吗？')) {
      return;
    }
    await _setParent(event.id);
  }

  Future<void> _chooseChild() async {
    final legalIds = (await widget.controller.childCandidates(_event.id))
        .map((event) => event.id)
        .toSet();
    if (!mounted) return;
    final result = await _choose(
      title: '选择下层事件',
      mode: _PickerMode.child,
      legalIds: legalIds,
    );
    final selected = result?.event;
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

  Future<_PickerResult?> _choose({
    required String title,
    required _PickerMode mode,
    required Set<String> legalIds,
    JaxEvent? existingParent,
  }) {
    final candidates = _categoryTree();
    final directChildren = widget.controller.worldEvents
        .where((event) => event.parentEventId == _event.id)
        .map((event) => event.id)
        .toSet();
    return showDialog<_PickerResult>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        content: SizedBox(
          width: 520,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .62,
            ),
            child: ListView(
              shrinkWrap: true,
              children: [
                if (mode == _PickerMode.parent) ...[
                  ListTile(
                    key: const ValueKey('hierarchy-no-parent'),
                    leading: const Icon(Icons.radio_button_unchecked),
                    title: const Text('无上层'),
                    trailing: existingParent == null
                        ? const Text('当前', style: TextStyle(fontSize: 12))
                        : null,
                    onTap: () => Navigator.pop(
                      context,
                      const _PickerResult.removeParent(),
                    ),
                  ),
                  const Divider(),
                ],
                for (final candidate in candidates)
                  _candidateTile(
                    context,
                    candidate,
                    mode: mode,
                    enabled: legalIds.contains(candidate.id),
                    existingParent: existingParent,
                    directChildren: directChildren,
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
        ],
      ),
    );
  }

  List<JaxEvent> _categoryTree() {
    final currentCategory = _effectiveCategoryId(_event);
    return widget.controller.worldEvents
        .where((event) => _effectiveCategoryId(event) == currentCategory)
        .toList(growable: false);
  }

  String? _effectiveCategoryId(JaxEvent event) {
    final byId = {
      for (final candidate in widget.controller.worldEvents)
        candidate.id: candidate,
    };
    var root = event;
    final visited = <String>{};
    while (root.parentEventId != null && visited.add(root.id)) {
      final parent = byId[root.parentEventId];
      if (parent == null) break;
      root = parent;
    }
    return root.categoryId;
  }

  Widget _candidateTile(
    BuildContext context,
    JaxEvent candidate, {
    required _PickerMode mode,
    required bool enabled,
    required JaxEvent? existingParent,
    required Set<String> directChildren,
  }) {
    final self = candidate.id == _event.id;
    final currentParent = candidate.id == existingParent?.id;
    final currentChild =
        mode == _PickerMode.child && directChildren.contains(candidate.id);
    final relation = self
        ? '当前事件'
        : currentParent
        ? '当前上层'
        : currentChild
        ? '当前下层'
        : !enabled
        ? mode == _PickerMode.parent && _isUnder(candidate, _event.id)
              ? '下层，不能作为上层'
              : mode == _PickerMode.child && _isUnder(_event, candidate.id)
              ? '上层，不能作为下层'
              : '当前状态不可选'
        : null;
    final depth = widget.controller.hierarchyDepthFor(candidate.id).clamp(0, 6);
    return Padding(
      padding: EdgeInsets.only(left: depth * 18.0),
      child: ListTile(
        key: ValueKey('hierarchy-candidate-${candidate.id}'),
        dense: true,
        enabled: enabled,
        leading: Icon(
          depth == 0
              ? Icons.account_tree_outlined
              : Icons.subdirectory_arrow_right,
          size: 18,
        ),
        title: Text(
          candidate.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: relation == null
            ? null
            : Text(
                relation,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
        onTap: enabled
            ? () => Navigator.pop(context, _PickerResult.event(candidate))
            : null,
      ),
    );
  }

  bool _isUnder(JaxEvent event, String ancestorId) {
    final byId = {
      for (final candidate in widget.controller.worldEvents)
        candidate.id: candidate,
    };
    var parentId = event.parentEventId;
    final visited = <String>{};
    while (parentId != null && visited.add(parentId)) {
      if (parentId == ancestorId) return true;
      parentId = byId[parentId]?.parentEventId;
    }
    return false;
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

enum _PickerMode { parent, child }

class _PickerResult {
  const _PickerResult.event(this.event) : removeParent = false;
  const _PickerResult.removeParent() : event = null, removeParent = true;

  final JaxEvent? event;
  final bool removeParent;
}
