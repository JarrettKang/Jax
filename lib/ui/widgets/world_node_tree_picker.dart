import 'package:flutter/material.dart';

import '../../core/entities/category.dart';
import '../../core/entities/world_node.dart';
import 'world_node_tree_guide.dart';

typedef WorldNodeDisabledReason = String? Function(WorldNode node);

/// Shared Category -> WorldNode hierarchy used by WorldNode selection flows.
class WorldNodeTreePicker extends StatefulWidget {
  const WorldNodeTreePicker({
    required this.categories,
    required this.worldNodes,
    required this.onSelected,
    required this.disabledReasonFor,
    required this.listKey,
    required this.categoryKeyPrefix,
    required this.nodeKeyPrefix,
    required this.branchKeyPrefix,
    this.initiallyExpandedCategoryIds,
    this.initiallyExpandedBranchIds,
    super.key,
  });

  final List<Category> categories;
  final List<WorldNode> worldNodes;
  final ValueChanged<WorldNode> onSelected;
  final WorldNodeDisabledReason disabledReasonFor;
  final Key listKey;
  final String categoryKeyPrefix;
  final String nodeKeyPrefix;
  final String branchKeyPrefix;

  /// Null means all sections/branches start expanded. An explicit set allows a
  /// caller such as the move picker to expand only the current location.
  final Set<String?>? initiallyExpandedCategoryIds;
  final Set<String>? initiallyExpandedBranchIds;

  @override
  State<WorldNodeTreePicker> createState() => _WorldNodeTreePickerState();
}

class _WorldNodeTreePickerState extends State<WorldNodeTreePicker> {
  late final Set<String> _expandedCategories;
  late final Set<String> _expandedBranches;

  @override
  void initState() {
    super.initState();
    _expandedCategories = widget.initiallyExpandedCategoryIds == null
        ? {
            ...widget.categories.map((category) => category.id),
            _unclassifiedKey,
          }
        : widget.initiallyExpandedCategoryIds!.map(_categoryKey).toSet();
    _expandedBranches = widget.initiallyExpandedBranchIds == null
        ? widget.worldNodes.map((node) => node.id).toSet()
        : {...widget.initiallyExpandedBranchIds!};
  }

  @override
  Widget build(BuildContext context) {
    if (widget.worldNodes.isEmpty) {
      return const Center(child: Text('暂无世界节点'));
    }
    return ListView(
      key: widget.listKey,
      children: [
        for (final category in <Category?>[...widget.categories, null])
          _categorySection(category),
      ],
    );
  }

  Widget _categorySection(Category? category) {
    final key = _categoryKey(category?.id);
    final roots =
        widget.worldNodes
            .where(
              (node) =>
                  node.parentWorldNodeId == null &&
                  node.categoryId == category?.id,
            )
            .toList()
          ..sort(_sortNodes);
    final expanded = _expandedCategories.contains(key);
    return Column(
      children: [
        ListTile(
          key: ValueKey('${widget.categoryKeyPrefix}$key'),
          dense: true,
          minLeadingWidth: 40,
          leading: Icon(expanded ? Icons.expand_more : Icons.chevron_right),
          title: Text(category?.name ?? '未分类'),
          subtitle: Text('${roots.length} 个根节点'),
          onTap: () => setState(() {
            expanded
                ? _expandedCategories.remove(key)
                : _expandedCategories.add(key);
          }),
        ),
        if (expanded)
          for (var index = 0; index < roots.length; index++)
            _nodeRow(
              roots[index],
              WorldNodeTreeVisualContext.root(
                isLastSibling: index == roots.length - 1,
              ),
            ),
      ],
    );
  }

  Widget _nodeRow(WorldNode node, WorldNodeTreeVisualContext visualContext) {
    final children =
        widget.worldNodes
            .where((candidate) => candidate.parentWorldNodeId == node.id)
            .toList()
          ..sort(_sortNodes);
    final expanded = _expandedBranches.contains(node.id);
    final disabledReason = widget.disabledReasonFor(node);
    return Column(
      children: [
        WorldNodeTreeGuideFrame(
          key: ValueKey('${widget.nodeKeyPrefix}guide-${node.id}'),
          visualContext: visualContext,
          child: ListTile(
            key: ValueKey('${widget.nodeKeyPrefix}${node.id}'),
            contentPadding: EdgeInsets.only(
              left: visualContext.contentIndent(),
              right: 8,
            ),
            dense: true,
            enabled: disabledReason == null,
            minLeadingWidth: 40,
            leading: children.isEmpty
                ? const SizedBox(
                    width: 40,
                    height: 40,
                    child: Icon(Icons.subdirectory_arrow_right, size: 20),
                  )
                : IconButton(
                    key: ValueKey('${widget.branchKeyPrefix}${node.id}'),
                    tooltip: expanded ? '折叠下级' : '展开下级',
                    constraints: const BoxConstraints.tightFor(
                      width: 40,
                      height: 40,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: () => setState(() {
                      expanded
                          ? _expandedBranches.remove(node.id)
                          : _expandedBranches.add(node.id);
                    }),
                    icon: Icon(
                      expanded ? Icons.expand_more : Icons.chevron_right,
                    ),
                  ),
            title: Text(
              node.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: disabledReason == null ? null : Text(disabledReason),
            onTap: disabledReason == null
                ? () => widget.onSelected(node)
                : null,
          ),
        ),
        if (expanded)
          for (var index = 0; index < children.length; index++)
            _nodeRow(
              children[index],
              visualContext.child(isLastSibling: index == children.length - 1),
            ),
      ],
    );
  }

  static const _unclassifiedKey = 'unclassified';

  static String _categoryKey(String? categoryId) =>
      categoryId ?? _unclassifiedKey;

  static int _sortNodes(WorldNode left, WorldNode right) {
    final order = left.sortOrder.compareTo(right.sortOrder);
    return order != 0 ? order : left.id.compareTo(right.id);
  }
}
