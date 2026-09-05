import 'package:flutter/material.dart';

/// Colour roles of the campus identity. Values and contrast ratios:
/// docs/design/design-direction.md §3.1. Names are roles, never values.
@immutable
class CampusColors extends ThemeExtension<CampusColors> {
  const CampusColors({
    required this.surface,
    required this.surfaceLowest,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.surfaceContainerHighest,
    required this.outline,
    required this.outlineVariant,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.onSurfaceMuted,
    required this.primary,
    required this.onPrimary,
    required this.now,
    required this.onNow,
    required this.nowContainer,
    required this.attention,
    required this.attentionContainer,
    required this.onAttentionContainer,
    required this.positive,
    required this.positiveContainer,
    required this.onPositiveContainer,
    required this.inverseSurface,
    required this.scrim,
  });

  final Color surface;
  final Color surfaceLowest;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;
  final Color surfaceContainerHighest;
  final Color outline;
  final Color outlineVariant;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color onSurfaceMuted;
  final Color primary;
  final Color onPrimary;

  /// The one accent. It means now, new, you. Never a text colour on light.
  final Color now;
  final Color onNow;
  final Color nowContainer;
  final Color attention;
  final Color attentionContainer;
  final Color onAttentionContainer;
  final Color positive;
  final Color positiveContainer;
  final Color onPositiveContainer;
  final Color inverseSurface;
  final Color scrim;

  static const CampusColors light = CampusColors(
    surface: Color(0xFFF4F5F7),
    surfaceLowest: Color(0xFFFFFFFF),
    surfaceContainer: Color(0xFFEBEDF1),
    surfaceContainerHigh: Color(0xFFE1E4EA),
    surfaceContainerHighest: Color(0xFFD5D9E0),
    outline: Color(0xFF7F8896),
    outlineVariant: Color(0xFFD5D9E0),
    onSurface: Color(0xFF1B2027),
    onSurfaceVariant: Color(0xFF5B6573),
    onSurfaceMuted: Color(0xFF7B8593),
    primary: Color(0xFF1B2027),
    onPrimary: Color(0xFFFFFFFF),
    now: Color(0xFFF2C12E),
    onNow: Color(0xFF1B2027),
    nowContainer: Color(0xFFFBF0C9),
    attention: Color(0xFFB8432F),
    attentionContainer: Color(0xFFFBE9E4),
    onAttentionContainer: Color(0xFF7A2A1C),
    positive: Color(0xFF2A7354),
    positiveContainer: Color(0xFFE3F1EA),
    onPositiveContainer: Color(0xFF1D5A40),
    inverseSurface: Color(0xFF1B2027),
    scrim: Color(0x66000000),
  );

  static const CampusColors dark = CampusColors(
    surface: Color(0xFF151A20),
    surfaceLowest: Color(0xFF151A20),
    surfaceContainer: Color(0xFF202730),
    surfaceContainerHigh: Color(0xFF262E38),
    surfaceContainerHighest: Color(0xFF2D3641),
    outline: Color(0xFF5D6977),
    outlineVariant: Color(0xFF38424E),
    onSurface: Color(0xFFF0F2F5),
    onSurfaceVariant: Color(0xFFA8B1BB),
    onSurfaceMuted: Color(0xFF7E8894),
    primary: Color(0xFFF0F2F5),
    onPrimary: Color(0xFF1B2027),
    now: Color(0xFFE8BD3F),
    onNow: Color(0xFF1B2027),
    nowContainer: Color(0xFF3A3418),
    attention: Color(0xFFE58A72),
    attentionContainer: Color(0xFF4A241C),
    onAttentionContainer: Color(0xFFF4C3B6),
    positive: Color(0xFF74C49B),
    positiveContainer: Color(0xFF1E3A2E),
    onPositiveContainer: Color(0xFFBFE6D1),
    inverseSurface: Color(0xFFF0F2F5),
    scrim: Color(0x99000000),
  );

  @override
  CampusColors copyWith({
    Color? surface,
    Color? surfaceLowest,
    Color? surfaceContainer,
    Color? surfaceContainerHigh,
    Color? surfaceContainerHighest,
    Color? outline,
    Color? outlineVariant,
    Color? onSurface,
    Color? onSurfaceVariant,
    Color? onSurfaceMuted,
    Color? primary,
    Color? onPrimary,
    Color? now,
    Color? onNow,
    Color? nowContainer,
    Color? attention,
    Color? attentionContainer,
    Color? onAttentionContainer,
    Color? positive,
    Color? positiveContainer,
    Color? onPositiveContainer,
    Color? inverseSurface,
    Color? scrim,
  }) => CampusColors(
    surface: surface ?? this.surface,
    surfaceLowest: surfaceLowest ?? this.surfaceLowest,
    surfaceContainer: surfaceContainer ?? this.surfaceContainer,
    surfaceContainerHigh: surfaceContainerHigh ?? this.surfaceContainerHigh,
    surfaceContainerHighest:
        surfaceContainerHighest ?? this.surfaceContainerHighest,
    outline: outline ?? this.outline,
    outlineVariant: outlineVariant ?? this.outlineVariant,
    onSurface: onSurface ?? this.onSurface,
    onSurfaceVariant: onSurfaceVariant ?? this.onSurfaceVariant,
    onSurfaceMuted: onSurfaceMuted ?? this.onSurfaceMuted,
    primary: primary ?? this.primary,
    onPrimary: onPrimary ?? this.onPrimary,
    now: now ?? this.now,
    onNow: onNow ?? this.onNow,
    nowContainer: nowContainer ?? this.nowContainer,
    attention: attention ?? this.attention,
    attentionContainer: attentionContainer ?? this.attentionContainer,
    onAttentionContainer: onAttentionContainer ?? this.onAttentionContainer,
    positive: positive ?? this.positive,
    positiveContainer: positiveContainer ?? this.positiveContainer,
    onPositiveContainer: onPositiveContainer ?? this.onPositiveContainer,
    inverseSurface: inverseSurface ?? this.inverseSurface,
    scrim: scrim ?? this.scrim,
  );

  @override
  CampusColors lerp(CampusColors? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return CampusColors(
      surface: mix(surface, other.surface),
      surfaceLowest: mix(surfaceLowest, other.surfaceLowest),
      surfaceContainer: mix(surfaceContainer, other.surfaceContainer),
      surfaceContainerHigh: mix(
        surfaceContainerHigh,
        other.surfaceContainerHigh,
      ),
      surfaceContainerHighest: mix(
        surfaceContainerHighest,
        other.surfaceContainerHighest,
      ),
      outline: mix(outline, other.outline),
      outlineVariant: mix(outlineVariant, other.outlineVariant),
      onSurface: mix(onSurface, other.onSurface),
      onSurfaceVariant: mix(onSurfaceVariant, other.onSurfaceVariant),
      onSurfaceMuted: mix(onSurfaceMuted, other.onSurfaceMuted),
      primary: mix(primary, other.primary),
      onPrimary: mix(onPrimary, other.onPrimary),
      now: mix(now, other.now),
      onNow: mix(onNow, other.onNow),
      nowContainer: mix(nowContainer, other.nowContainer),
      attention: mix(attention, other.attention),
      attentionContainer: mix(attentionContainer, other.attentionContainer),
      onAttentionContainer: mix(
        onAttentionContainer,
        other.onAttentionContainer,
      ),
      positive: mix(positive, other.positive),
      positiveContainer: mix(positiveContainer, other.positiveContainer),
      onPositiveContainer: mix(onPositiveContainer, other.onPositiveContainer),
      inverseSurface: mix(inverseSurface, other.inverseSurface),
      scrim: mix(scrim, other.scrim),
    );
  }
}

/// The two numeric text roles Material's TextTheme has no slot for.
@immutable
class CampusTypography extends ThemeExtension<CampusTypography> {
  const CampusTypography({required this.displayNumeral, required this.numeral});

  /// 40/44, weight 600, tabular figures. Semester average, temperature now.
  final TextStyle displayNumeral;

  /// 16/20, weight 600, tabular figures. Grades in rows, times.
  final TextStyle numeral;

  @override
  CampusTypography copyWith({TextStyle? displayNumeral, TextStyle? numeral}) =>
      CampusTypography(
        displayNumeral: displayNumeral ?? this.displayNumeral,
        numeral: numeral ?? this.numeral,
      );

  @override
  CampusTypography lerp(CampusTypography? other, double t) {
    if (other == null) return this;
    return CampusTypography(
      displayNumeral: TextStyle.lerp(displayNumeral, other.displayNumeral, t)!,
      numeral: TextStyle.lerp(numeral, other.numeral, t)!,
    );
  }
}

/// 4 dp scale. docs/design/design-direction.md §3.3.
abstract final class CampusSpacing {
  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x5 = 20;
  static const double x6 = 24;
  static const double x8 = 32;
  static const double x10 = 40;
  static const double gutter = 16;
  static const double card = 16;
  static const double rowMinHeight = 56;
  static const double touchTarget = 48;
}

abstract final class CampusRadii {
  /// Cap on a chart bar. Smaller than any control radius because a 6 dp wide
  /// histogram bar rounded to 8 would lose its shape entirely.
  static const double bar = 3;
  static const double control = 8;
  static const double card = 12;
  static const double sheet = 20;
  static const BorderRadius controlRadius = BorderRadius.all(
    Radius.circular(control),
  );
  static const BorderRadius cardRadius = BorderRadius.all(
    Radius.circular(card),
  );
  static const BorderRadius sheetRadius = BorderRadius.vertical(
    top: Radius.circular(sheet),
  );
}

abstract final class CampusMotion {
  static const Duration fast = Duration(milliseconds: 100);
  static const Duration exit = Duration(milliseconds: 200);
  static const Duration enter = Duration(milliseconds: 300);
  static const Duration surface = Duration(milliseconds: 400);
  static const Curve standard = Easing.standard;
  static const Curve enterCurve = Easing.emphasizedDecelerate;
  static const Curve exitCurve = Easing.emphasizedAccelerate;

  /// Every animated widget asks here so the OS "remove animations" setting
  /// collapses motion to zero app-wide.
  static Duration of(BuildContext context, Duration duration) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
}
