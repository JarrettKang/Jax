import 'package:flutter/material.dart';

import 'home_pilot_theme.dart';

/// Planning-only application of docs/DESIGN.md v1.0. Reuses the adopted
/// palette/type values without modifying Home or the application theme.
abstract final class PlanningTheme {
  static const error = Color(0xFFA33D36);

  static EdgeInsets pagePadding(BuildContext context) => EdgeInsets.fromLTRB(
    Theme.of(context).platform == TargetPlatform.windows ? 24 : 16,
    24,
    Theme.of(context).platform == TargetPlatform.windows ? 24 : 16,
    48,
  );

  static OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(HomePilot.buttonRadius),
        borderSide: BorderSide(color: color, width: width),
      );

  static ThemeData of(ThemeData base) {
    final adopted = HomePilot.theme(base);
    return adopted.copyWith(
      scaffoldBackgroundColor: HomePilot.canvas,
      colorScheme: adopted.colorScheme.copyWith(error: error),
      hoverColor: HomePilot.surfaceSubtle,
      dividerTheme: const DividerThemeData(
        color: HomePilot.hairline,
        thickness: 1,
        space: 25,
      ),
      inputDecorationTheme: InputDecorationTheme(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: border(HomePilot.hairlineStrong),
        enabledBorder: border(HomePilot.hairlineStrong),
        focusedBorder: border(HomePilot.accent, 2),
        errorBorder: border(error),
        focusedErrorBorder: border(error, 2),
        errorMaxLines: 4,
      ),
      iconButtonTheme: IconButtonThemeData(
        style: HomePilot.buttonStyle().copyWith(
          iconSize: const WidgetStatePropertyAll(18),
          foregroundColor: const WidgetStatePropertyAll(
            HomePilot.textSecondary,
          ),
        ),
      ),
      listTileTheme: ListTileThemeData(
        titleTextStyle: adopted.textTheme.titleMedium,
        subtitleTextStyle: adopted.textTheme.bodySmall,
        iconColor: HomePilot.textSecondary,
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        shape: Border(),
        collapsedShape: Border(),
        iconColor: HomePilot.textSecondary,
        collapsedIconColor: HomePilot.textSecondary,
      ),
    );
  }

  static ButtonStyle get destructive => HomePilot.buttonStyle().copyWith(
    backgroundColor: const WidgetStatePropertyAll(error),
    foregroundColor: const WidgetStatePropertyAll(HomePilot.surface),
  );
}

class PlanningVisualScope extends StatelessWidget {
  const PlanningVisualScope({required this.builder, super.key});
  final WidgetBuilder builder;
  @override
  Widget build(BuildContext context) => Theme(
    data: PlanningTheme.of(Theme.of(context)),
    child: Builder(builder: builder),
  );
}

/// Focus feedback preserves the row's size and the InkWell's keyboard behavior.
class PlanningRowSurface extends StatefulWidget {
  const PlanningRowSurface({required this.child, this.onTap, super.key});
  final Widget child;
  final VoidCallback? onTap;
  @override
  State<PlanningRowSurface> createState() => _PlanningRowSurfaceState();
}

class _PlanningRowSurfaceState extends State<PlanningRowSurface> {
  bool _focused = false;
  bool _hovered = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: _hovered ? HomePilot.surfaceSubtle : null,
        border: Border.all(
          color: _focused ? HomePilot.accent : Colors.transparent,
          width: 2,
        ),
      ),
      child: widget.onTap == null
          ? widget.child
          : InkWell(
              onTap: widget.onTap,
              onFocusChange: (value) => setState(() => _focused = value),
              child: widget.child,
            ),
    ),
  );
}
