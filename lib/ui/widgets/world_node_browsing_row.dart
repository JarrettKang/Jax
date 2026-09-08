import 'package:flutter/material.dart';

/// World-only gesture policy. Pickers keep their node-selection interactions.
class WorldNodeBrowsingRow extends StatelessWidget {
  const WorldNodeBrowsingRow({
    required this.mainKey,
    required this.leading,
    required this.hasChildren,
    required this.title,
    required this.more,
    required this.indent,
    required this.onBrowse,
    required this.onAttention,
    required this.browseHint,
    super.key,
  });

  final Key mainKey;
  final Widget leading;
  final bool hasChildren;
  final Widget title;
  final Widget more;
  final double indent;
  final VoidCallback? onBrowse;
  final VoidCallback onAttention;
  final String? browseHint;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(left: indent),
    child: Row(
      children: [
        // These controls are siblings of the recognizer, never descendants.
        // Even two fast chevron taps cannot join the attention gesture arena.
        if (hasChildren) leading,
        Expanded(
          child: Semantics(
            key: mainKey,
            container: true,
            onTap: onBrowse,
            onTapHint: browseHint,
            child: InkWell(
              onTap: onBrowse,
              onDoubleTap: onAttention,
              // TalkBack activation must browse, not invoke the pointer-only
              // double-tap shortcut. Attention remains accessible via More.
              excludeFromSemantics: true,
              child: ListTile(
                dense: true,
                minTileHeight: 48,
                minVerticalPadding: 0,
                horizontalTitleGap: 0,
                minLeadingWidth: 48,
                contentPadding: const EdgeInsets.only(right: 16),
                leading: hasChildren ? null : leading,
                title: title,
              ),
            ),
          ),
        ),
        more,
      ],
    ),
  );
}
