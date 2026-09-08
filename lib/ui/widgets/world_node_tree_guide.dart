import 'dart:math' as math;

import 'package:flutter/material.dart';

@immutable
class WorldNodeTreeVisualContext {
  const WorldNodeTreeVisualContext._({
    required this.depth,
    required this.ancestorHasNextSibling,
    required this.isLastSibling,
  });

  const WorldNodeTreeVisualContext.root({required bool isLastSibling})
    : this._(
        depth: 0,
        ancestorHasNextSibling: const [],
        isLastSibling: isLastSibling,
      );

  final int depth;

  /// Continuation state for guide columns above the current parent level.
  /// Root nodes have none; a depth-N row has N-1 entries.
  final List<bool> ancestorHasNextSibling;
  final bool isLastSibling;

  double contentIndent({
    double baseIndent = 12,
    double levelIndent = 18,
    int maximumVisualDepth = 7,
  }) => baseIndent + math.min(depth, maximumVisualDepth) * levelIndent;

  WorldNodeTreeVisualContext child({required bool isLastSibling}) =>
      WorldNodeTreeVisualContext._(
        depth: depth + 1,
        ancestorHasNextSibling: depth == 0
            ? const []
            : [...ancestorHasNextSibling, !this.isLastSibling],
        isLastSibling: isLastSibling,
      );
}

/// Paints non-semantic hierarchy guides behind an otherwise interactive row.
class WorldNodeTreeGuideFrame extends StatelessWidget {
  const WorldNodeTreeGuideFrame({
    required this.visualContext,
    required this.child,
    this.baseIndent = 12,
    this.levelIndent = 18,
    this.maximumVisualDepth = 7,
    this.nodeLeadingWidth = 40,
    this.hasExpandedChildren = false,
    super.key,
  });

  final WorldNodeTreeVisualContext visualContext;
  final Widget child;
  final double baseIndent;
  final double levelIndent;
  final int maximumVisualDepth;
  final double nodeLeadingWidth;
  final bool hasExpandedChildren;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      if (visualContext.depth > 0 || hasExpandedChildren)
        Positioned.fill(
          child: ExcludeSemantics(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _WorldNodeTreeGuidePainter(
                  visualContext: visualContext,
                  color: Theme.of(context).colorScheme.outlineVariant
                      .withValues(alpha: 0.9),
                  baseIndent: baseIndent,
                  levelIndent: levelIndent,
                  maximumVisualDepth: maximumVisualDepth,
                  nodeLeadingWidth: nodeLeadingWidth,
                  hasExpandedChildren: hasExpandedChildren,
                ),
              ),
            ),
          ),
        ),
      child,
    ],
  );
}

class _WorldNodeTreeGuidePainter extends CustomPainter {
  const _WorldNodeTreeGuidePainter({
    required this.visualContext,
    required this.color,
    required this.baseIndent,
    required this.levelIndent,
    required this.maximumVisualDepth,
    required this.nodeLeadingWidth,
    required this.hasExpandedChildren,
  });

  final WorldNodeTreeVisualContext visualContext;
  final Color color;
  final double baseIndent;
  final double levelIndent;
  final int maximumVisualDepth;
  final double nodeLeadingWidth;
  final bool hasExpandedChildren;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final priorColumns = math.min(
      visualContext.ancestorHasNextSibling.length,
      maximumVisualDepth - 1,
    );
    for (var index = 0; index < priorColumns; index++) {
      if (!visualContext.ancestorHasNextSibling[index]) continue;
      final x = baseIndent + nodeLeadingWidth / 2 + index * levelIndent;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    final middle = size.height / 2;
    // The parent axis is the centre of its leading control, not an arbitrary
    // midpoint in the indent. This joins the parent's outgoing stem exactly.
    if (visualContext.depth > 0) {
      final currentColumn = math.min(
        visualContext.depth - 1,
        maximumVisualDepth - 1,
      );
      final x = baseIndent + nodeLeadingWidth / 2 + currentColumn * levelIndent;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, visualContext.isLastSibling ? middle : size.height),
        paint,
      );
      canvas.drawLine(
        Offset(x, middle),
        Offset(x + levelIndent - 5, middle),
        paint,
      );
    }
    if (hasExpandedChildren && visualContext.depth < maximumVisualDepth) {
      final x =
          baseIndent + nodeLeadingWidth / 2 + visualContext.depth * levelIndent;
      canvas.drawLine(Offset(x, middle + 9), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_WorldNodeTreeGuidePainter oldDelegate) =>
      oldDelegate.visualContext.depth != visualContext.depth ||
      oldDelegate.visualContext.isLastSibling != visualContext.isLastSibling ||
      !_sameContinuations(
        oldDelegate.visualContext.ancestorHasNextSibling,
        visualContext.ancestorHasNextSibling,
      ) ||
      oldDelegate.color != color ||
      oldDelegate.baseIndent != baseIndent ||
      oldDelegate.levelIndent != levelIndent ||
      oldDelegate.maximumVisualDepth != maximumVisualDepth ||
      oldDelegate.nodeLeadingWidth != nodeLeadingWidth ||
      oldDelegate.hasExpandedChildren != hasExpandedChildren;

  static bool _sameContinuations(List<bool> left, List<bool> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}
