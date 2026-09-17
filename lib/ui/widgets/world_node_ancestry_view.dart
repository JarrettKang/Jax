import 'package:flutter/material.dart';

import 'world_node_tree_guide.dart';

/// Read-only ancestor chain. Callers supply context labels explicitly;
/// category metadata is never inferred from WorldNode names.
class WorldNodeAncestryView extends StatelessWidget {
  const WorldNodeAncestryView({
    required this.names,
    this.compact = false,
    this.textStyle,
    this.guideColor,
    super.key,
  });
  final List<String> names;
  final bool compact;
  final TextStyle? textStyle;
  final Color? guideColor;

  @override
  Widget build(BuildContext context) {
    if (names.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    var visual = const WorldNodeTreeVisualContext.root(isLastSibling: true);
    final rows = <Widget>[];
    for (var index = 0; index < names.length; index++) {
      if (index > 0) visual = visual.child(isLastSibling: true);
      rows.add(
        WorldNodeTreeGuideFrame(
          visualContext: visual,
          guideColor:
              guideColor ??
              (compact
                  ? theme.colorScheme.outlineVariant.withValues(alpha: 0.55)
                  : null),
          baseIndent: 0,
          levelIndent: 12,
          maximumVisualDepth: 5,
          nodeLeadingWidth: 0,
          hasExpandedChildren: index < names.length - 1,
          child: Padding(
            padding: EdgeInsets.only(
              left: visual.contentIndent(
                baseIndent: 0,
                levelIndent: 12,
                maximumVisualDepth: 5,
              ),
              top: compact ? 1 : 2,
              bottom: compact ? 1 : 2,
            ),
            child: Text(
              names[index],
              softWrap: true,
              style:
                  textStyle ??
                  theme.textTheme.bodySmall?.copyWith(
                    fontSize: compact ? 11 : null,
                    color: compact
                        ? theme.colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.8,
                          )
                        : theme.colorScheme.onSurfaceVariant,
                    height: compact ? 1.2 : 1.3,
                  ),
            ),
          ),
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }
}
