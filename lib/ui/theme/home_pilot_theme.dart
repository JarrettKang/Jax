import 'package:flutter/material.dart';

/// Experimental Home-only values. Not the application design system.
abstract final class HomePilot {
  static const canvas = Color(0xFFF7F7F3);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceSubtle = Color(0xFFEFEFE9);
  static const textPrimary = Color(0xFF252A27);
  static const textSecondary = Color(0xFF555E58);
  static const textMuted = Color(0xFF68716B);
  static const hairline = Color(0xFFDDE1DA);
  static const hairlineStrong = Color(0xFF818B83);
  static const accent = Color(0xFF315C4C);
  static const accentSubtle = Color(0xFFE7EFEA);
  static const warning = Color(0xFF865C19);
  static const buttonRadius = 8.0;
  static const heroRadius = 16.0;
  static const maxWidth = 820.0;

  static ButtonStyle buttonStyle({
    bool outlined = false,
    bool primary = false,
  }) => ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
    visualDensity: VisualDensity.standard,
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    ),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(buttonRadius)),
    ),
    side: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.focused)) {
        return const BorderSide(color: accent, width: 2);
      }
      return BorderSide(color: outlined ? hairlineStrong : Colors.transparent);
    }),
    backgroundColor: primary
        ? WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.focused) ? accentSubtle : null,
          )
        : null,
    foregroundColor: primary
        ? WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.focused) ? accent : null,
          )
        : null,
    overlayColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.hovered)
          ? accent.withValues(alpha: .08)
          : null,
    ),
  );

  static ThemeData theme(ThemeData base) {
    TextStyle style(
      TextStyle? original,
      double size,
      FontWeight weight,
      double height,
      Color color,
    ) => (original ?? const TextStyle()).copyWith(
      fontSize: size,
      fontWeight: weight,
      height: height,
      color: color,
      letterSpacing: 0,
    );
    final text = base.textTheme;
    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        primary: accent,
        onPrimary: surface,
        surface: canvas,
        onSurface: textPrimary,
        onSurfaceVariant: textSecondary,
        outline: hairlineStrong,
        outlineVariant: hairline,
      ),
      textTheme: text.copyWith(
        headlineMedium: style(
          text.headlineMedium,
          26,
          FontWeight.w600,
          1.3,
          textPrimary,
        ),
        titleLarge: style(
          text.titleLarge,
          17,
          FontWeight.w600,
          1.4,
          textPrimary,
        ),
        titleMedium: style(
          text.titleMedium,
          16,
          FontWeight.w500,
          1.45,
          textPrimary,
        ),
        bodyMedium: style(
          text.bodyMedium,
          14,
          FontWeight.w400,
          1.5,
          textSecondary,
        ),
        bodySmall: style(text.bodySmall, 13, FontWeight.w400, 1.45, textMuted),
        labelLarge: style(
          text.labelLarge,
          14,
          FontWeight.w500,
          1.4,
          textSecondary,
        ),
        displaySmall: style(
          text.displaySmall,
          32,
          FontWeight.w500,
          1.3,
          textPrimary,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: buttonStyle().copyWith(
          foregroundColor: const WidgetStatePropertyAll(textSecondary),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: buttonStyle(outlined: true),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: buttonStyle(primary: true),
      ),
    );
  }
}

/// Hover feedback without making the entire action row a new click target.
class HomePilotHoverRow extends StatefulWidget {
  const HomePilotHoverRow({required this.child, super.key});
  final Widget child;
  @override
  State<HomePilotHoverRow> createState() => _HomePilotHoverRowState();
}

class _HomePilotHoverRowState extends State<HomePilotHoverRow> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: ColoredBox(
      color: _hovered ? HomePilot.surfaceSubtle : Colors.transparent,
      child: widget.child,
    ),
  );
}
