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
    super.key,
  });

  final WorldNodeTreeVisualContext visualContext;
  final Widget child;
  final double baseIndent;
  final double levelIndent;
  final int maximumVisualDepth;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      if (visualContext.depth > 0)
        Positioned.fill(
          child: ExcludeSemantics(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _WorldNodeTreeGuidePainter(
                  visualContext: visualContext,
                  color: Theme.of(context).colorScheme.outlineVariant
                      .withValues(alpha: 0.58),
                  baseIndent: baseIndent,
                  levelIndent: levelIndent,
                  maximumVisualDepth: maximumVisualDepth,
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
  });

  final WorldNodeTreeVisualContext visualContext;
  final Color color;
  final double baseIndent;
  final double levelIndent;
  final int maximumVisualDepth;

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
      final x = baseIndent + (index + .5) * levelIndent;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    final currentColumn = math.min(
      visualContext.depth - 1,
      maximumVisualDepth - 1,
    );
    final x = baseIndent + (currentColumn + .5) * levelIndent;
    final middle = size.height / 2;
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, visualContext.isLastSibling ? middle : size.height),
      paint,
    );
    canvas.drawLine(
      Offset(x, middle),
      Offset(baseIndent + (currentColumn + 1) * levelIndent, middle),
      paint,
    );
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
      oldDelegate.maximumVisualDepth != maximumVisualDepth;

  static bool _sameContinuations(List<bool> left, List<bool> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}
