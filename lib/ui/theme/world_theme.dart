import 'package:flutter/material.dart';

import 'home_pilot_theme.dart';
import 'planning_theme.dart';

/// World-local adoption of the v1.0 palette and control tokens. No app-wide
/// theme changes; the full tree has its own width and density.
abstract final class WorldTheme {
  static const levelIndent = 16.0;
  static const maximumVisualDepth = 3;
  // Preserve roughly five title glyphs at enlarged text sizes. Full relation
  // labels take over when the available width compresses the visible depth.
  static int depthLimit(BuildContext context, double width) =>
      ((width - 104 - MediaQuery.textScalerOf(context).scale(16) * 5) /
              levelIndent)
          .floor()
          .clamp(1, maximumVisualDepth);
  static const structuralWidth = 1040.0;
  static EdgeInsets pagePadding(BuildContext context) => EdgeInsets.fromLTRB(
    Theme.of(context).platform == TargetPlatform.windows ? 24 : 16,
    16,
    Theme.of(context).platform == TargetPlatform.windows ? 24 : 16,
    48,
  );
  static ThemeData of(ThemeData base) {
    final adopted = PlanningTheme.of(base);
    return adopted.copyWith(
      dialogTheme: DialogThemeData(
        backgroundColor: HomePilot.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: adopted.textTheme.titleLarge,
        contentTextStyle: adopted.textTheme.bodyMedium,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: HomePilot.surface,
        surfaceTintColor: Colors.transparent,
        textStyle: adopted.textTheme.bodyMedium,
      ),
    );
  }
}

class WorldVisualScope extends StatelessWidget {
  const WorldVisualScope({required this.builder, super.key});
  final WidgetBuilder builder;
  @override
  Widget build(BuildContext context) => Theme(
    data: WorldTheme.of(Theme.of(context)),
    child: Builder(builder: builder),
  );
}

/// Feedback changes paint only, leaving the connector and row geometry stable.
class WorldRowSurface extends StatefulWidget {
  const WorldRowSurface({required this.child, required this.onTap, super.key});
  final Widget child;
  final VoidCallback? onTap;
  @override
  State<WorldRowSurface> createState() => _WorldRowSurfaceState();
}

class _WorldRowSurfaceState extends State<WorldRowSurface> {
  bool _focused = false;
  @override
  Widget build(BuildContext context) => Container(
    foregroundDecoration: BoxDecoration(
      border: Border.all(
        color: _focused ? HomePilot.accent : Colors.transparent,
        width: 2,
      ),
    ),
    child: InkWell(
      onTap: widget.onTap,
      onFocusChange: (value) => setState(() => _focused = value),
      hoverColor: HomePilot.surfaceSubtle,
      focusColor: Colors.transparent,
      child: widget.child,
    ),
  );
}
