import '../theme/list_density.dart';

import 'package:flutter/material.dart';

import '../theme/world_theme.dart';

/// World-only gesture policy. Pickers keep their node-selection interactions.
class WorldNodeBrowsingRow extends StatelessWidget {
  const WorldNodeBrowsingRow({
    this.density = JaxListDensity.standard,
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

  final JaxListDensity density;
  final Key mainKey;
  final Widget leading;
  final bool hasChildren;
  final Widget title;
  final Widget more;
  final double indent;
  final VoidCallback? onBrowse;
  final VoidCallback? onAttention;
  final String? browseHint;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(left: indent),
    child: Row(
      children: [
        // These controls are siblings of the recognizer, never descendants.
        if (hasChildren) leading,
        Expanded(
          child: Semantics(
            key: mainKey,
            container: true,
            onTap: hasChildren ? onBrowse : onAttention,
            onTapHint: browseHint,
            child: MergeSemantics(
              child: WorldRowSurface(
                onTap: hasChildren ? onBrowse : onAttention,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Row(
                    children: [
                      if (!hasChildren) leading,
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: density == JaxListDensity.compact ? 4 : 8,
                            horizontal: 4,
                          ),
                          child: title,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        more,
      ],
    ),
  );
}
