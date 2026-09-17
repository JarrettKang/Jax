import 'package:flutter/material.dart';

import 'home_pilot_theme.dart';
import 'planning_theme.dart';

/// Explicit Phase C scope; existing Home/Planning/World callers are unaffected.
abstract final class OperationalTheme {
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

  static EdgeInsets pagePadding(BuildContext context) => EdgeInsets.fromLTRB(
    Theme.of(context).platform == TargetPlatform.windows ? 24 : 16,
    16,
    Theme.of(context).platform == TargetPlatform.windows ? 24 : 16,
    48,
  );
}

class OperationalVisualScope extends StatelessWidget {
  const OperationalVisualScope({required this.builder, super.key});
  final WidgetBuilder builder;
  @override
  Widget build(BuildContext context) => Theme(
    data: OperationalTheme.of(Theme.of(context)),
    child: Builder(builder: builder),
  );
}
