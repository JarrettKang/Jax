import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'home_pilot_theme.dart';
import 'planning_theme.dart';

enum DesktopDialogSize { confirmation, form, complex }

abstract final class DesktopPolish {
  static ThemeData theme(ThemeData base) {
    if (base.platform != TargetPlatform.windows) return base;
    final adopted = PlanningTheme.of(base);
    return adopted.copyWith(
      textTheme: base.textTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: HomePilot.canvas,
        foregroundColor: HomePilot.textPrimary,
        surfaceTintColor: Colors.transparent,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(6),
        radius: const Radius.circular(4),
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.dragged)
              ? HomePilot.textSecondary
              : HomePilot.hairlineStrong,
        ),
      ),
    );
  }

  static BoxConstraints? dialog(BuildContext context, DesktopDialogSize size) {
    if (Theme.of(context).platform != TargetPlatform.windows) return null;
    final target = switch (size) {
      DesktopDialogSize.confirmation => 400.0,
      DesktopDialogSize.form => 560.0,
      DesktopDialogSize.complex => 720.0,
    };
    final width = math
        .min(target, math.max(0, MediaQuery.sizeOf(context).width - 80))
        .toDouble();
    return BoxConstraints(minWidth: width, maxWidth: width);
  }
}

class JaxScrollBehavior extends MaterialScrollBehavior {
  const JaxScrollBehavior();
  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    if (Theme.of(context).platform != TargetPlatform.windows) {
      return super.buildScrollbar(context, child, details);
    }
    if (axisDirectionToAxis(details.direction) == Axis.horizontal) return child;
    return Scrollbar(
      controller: details.controller,
      thumbVisibility: true,
      child: child,
    );
  }
}
