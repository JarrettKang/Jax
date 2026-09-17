import 'package:flutter/material.dart';

import '../../core/entities/category.dart';
import '../../core/entities/world_node.dart';
import 'world_node_tree_guide.dart';
import '../theme/world_theme.dart';
import '../theme/home_pilot_theme.dart';

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
    this.worldVisuals = false,
    this.header,
    this.initiallyExpandedCategoryIds,
    this.initiallyExpandedBranchIds,
    super.key,
  });

  final bool worldVisuals;
  final Widget? header;
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
  int _depthLimit = WorldTheme.maximumVisualDepth;
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
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _depthLimit = WorldTheme.depthLimit(context, constraints.maxWidth);
      if (widget.worldNodes.isEmpty) {
        return const Center(child: Text('暂无世界节点'));
      }
      return ListView(
        key: widget.listKey,
        children: [
          if (widget.header != null) widget.header!,
          for (final category in <Category?>[...widget.categories, null])
            _categorySection(category),
        ],
      );
    },
  );

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
    void toggle() => setState(() {
      expanded ? _expandedCategories.remove(key) : _expandedCategories.add(key);
    });
    final heading = ListTile(
      key: ValueKey('${widget.categoryKeyPrefix}$key'),
      dense: true,
      minTileHeight: widget.worldVisuals ? 48 : null,
      contentPadding: widget.worldVisuals ? EdgeInsets.zero : null,
      minLeadingWidth: 40,
      leading: Icon(expanded ? Icons.expand_more : Icons.chevron_right),
      title: Text(
        category?.name ?? '未分类',
        style: widget.worldVisuals
            ? Theme.of(context).textTheme.titleLarge
            : null,
      ),
      subtitle: widget.worldVisuals ? null : Text('${roots.length} 个根节点'),
      onTap: widget.worldVisuals ? null : toggle,
    );
    return Column(
      children: [
        if (widget.worldVisuals)
          WorldRowSurface(onTap: toggle, child: heading)
        else
          heading,
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
          hasExpandedChildren: expanded && children.isNotEmpty,
          baseIndent: widget.worldVisuals ? 0 : 12,
          levelIndent: widget.worldVisuals ? WorldTheme.levelIndent : 18,
          maximumVisualDepth: widget.worldVisuals ? _depthLimit : 7,
          nodeLeadingWidth: widget.worldVisuals ? 48 : 40,
          guideColor: widget.worldVisuals ? HomePilot.hairlineStrong : null,
          continueAtMaximumDepth: widget.worldVisuals,
          paintAboveChild: widget.worldVisuals,

          child: widget.worldVisuals
              ? _visualNode(
                  node,
                  visualContext,
                  children,
                  expanded,
                  disabledReason,
                )
              : ListTile(
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
                  subtitle: disabledReason == null
                      ? null
                      : Text(disabledReason),
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

  Widget _visualNode(
    WorldNode node,
    WorldNodeTreeVisualContext visual,
    List<WorldNode> children,
    bool expanded,
    String? disabledReason,
  ) {
    final parent = widget.worldNodes
        .where((n) => n.id == node.parentWorldNodeId)
        .firstOrNull;
    return Padding(
      padding: EdgeInsets.only(
        left: visual.contentIndent(
          baseIndent: 0,
          levelIndent: WorldTheme.levelIndent,
          maximumVisualDepth: _depthLimit,
        ),
      ),
      child: Row(
        children: [
          if (children.isNotEmpty)
            IconButton(
              key: ValueKey('${widget.branchKeyPrefix}${node.id}'),
              tooltip: expanded ? '折叠下级' : '展开下级',
              onPressed: () => setState(() {
                expanded
                    ? _expandedBranches.remove(node.id)
                    : _expandedBranches.add(node.id);
              }),
              icon: Icon(expanded ? Icons.expand_more : Icons.chevron_right),
            )
          else
            const SizedBox(
              width: 48,
              height: 48,
              child: Icon(
                Icons.circle_outlined,
                size: 8,
                color: HomePilot.textMuted,
              ),
            ),
          Expanded(
            child: WorldRowSurface(
              key: ValueKey('${widget.nodeKeyPrefix}${node.id}'),
              onTap: disabledReason == null
                  ? () => widget.onSelected(node)
                  : null,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 4,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        node.name,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: disabledReason == null
                                  ? HomePilot.textPrimary
                                  : HomePilot.textMuted,
                            ),
                      ),
                      if (visual.depth > _depthLimit)
                        Text(
                          '第 ${visual.depth + 1} 层 · 上层：${parent?.name ?? ""}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      if (disabledReason != null)
                        Text(
                          disabledReason,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
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
