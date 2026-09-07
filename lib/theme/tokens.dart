import 'package:flutter/foundation.dart';
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
    required this.moduleTints,
    required this.moduleTintsBold,
    required this.moduleBlockTints,
    required this.moduleSpineTints,
    required this.moduleBarTints,
    required this.onModuleBlockTint,
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

  /// Block fills for timetable modules, generated in OKLCH at the weight of
  /// [surfaceContainerHighest] so a tinted block reads no heavier than a plain
  /// one. The 40-115 degree hue band is left empty: that is [now].
  final List<Color> moduleTints;

  /// The same hues at bar density, for the week strip, where the bar carries
  /// the information itself and so needs 3:1 against the surface rather than
  /// the fill weight of [moduleTints].
  final List<Color> moduleTintsBold;

  /// The grid block fill. Empty when the chosen scheme or intensity leaves
  /// blocks neutral, which ModulePalette resolves to its fallback.
  final List<Color> moduleBlockTints;

  /// The 3 dp spine on a timeline row, and so on the hub preview.
  final List<Color> moduleSpineTints;

  /// The week strip bar, which carries its information with no text.
  final List<Color> moduleBarTints;

  /// The label ink on a grid block. Never a new colour: onSurface on a pale
  /// fill, surfaceLowest on a Vif block.
  final Color onModuleBlockTint;

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
    moduleTints: <Color>[
      Color(0xFFD0DDB9),
      Color(0xFFBDE1C9),
      Color(0xFFB2E2DD),
      Color(0xFFB4DFEF),
      Color(0xFFC1D9F8),
      Color(0xFFD3D3F7),
      Color(0xFFE6CDEC),
      Color(0xFFF2CADA),
    ],
    moduleTintsBold: <Color>[
      Color(0xFF5C7327),
      Color(0xFF297A4F),
      Color(0xFF007B75),
      Color(0xFF007594),
      Color(0xFF3B6BA4),
      Color(0xFF645FA2),
      Color(0xFF83548F),
      Color(0xFF964D6F),
    ],
    moduleBlockTints: <Color>[
      Color(0xFFD0DDB9),
      Color(0xFFBDE1C9),
      Color(0xFFB2E2DD),
      Color(0xFFB4DFEF),
      Color(0xFFC1D9F8),
      Color(0xFFD3D3F7),
      Color(0xFFE6CDEC),
      Color(0xFFF2CADA),
    ],
    moduleSpineTints: <Color>[
      Color(0xFFD0DDB9),
      Color(0xFFBDE1C9),
      Color(0xFFB2E2DD),
      Color(0xFFB4DFEF),
      Color(0xFFC1D9F8),
      Color(0xFFD3D3F7),
      Color(0xFFE6CDEC),
      Color(0xFFF2CADA),
    ],
    moduleBarTints: <Color>[
      Color(0xFF5C7327),
      Color(0xFF297A4F),
      Color(0xFF007B75),
      Color(0xFF007594),
      Color(0xFF3B6BA4),
      Color(0xFF645FA2),
      Color(0xFF83548F),
      Color(0xFF964D6F),
    ],
    onModuleBlockTint: Color(0xFF1B2027),
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
    moduleTints: <Color>[
      Color(0xFF2E371B),
      Color(0xFF1D3A28),
      Color(0xFF0D3B38),
      Color(0xFF113844),
      Color(0xFF21344B),
      Color(0xFF312F4A),
      Color(0xFF3D2B42),
      Color(0xFF462835),
    ],
    moduleTintsBold: <Color>[
      Color(0xFF92A965),
      Color(0xFF6BB086),
      Color(0xFF4BB1AA),
      Color(0xFF52ACC9),
      Color(0xFF75A1D9),
      Color(0xFF9996D7),
      Color(0xFFB88BC4),
      Color(0xFFCC86A5),
    ],
    moduleBlockTints: <Color>[
      Color(0xFF2E371B),
      Color(0xFF1D3A28),
      Color(0xFF0D3B38),
      Color(0xFF113844),
      Color(0xFF21344B),
      Color(0xFF312F4A),
      Color(0xFF3D2B42),
      Color(0xFF462835),
    ],
    moduleSpineTints: <Color>[
      Color(0xFF2E371B),
      Color(0xFF1D3A28),
      Color(0xFF0D3B38),
      Color(0xFF113844),
      Color(0xFF21344B),
      Color(0xFF312F4A),
      Color(0xFF3D2B42),
      Color(0xFF462835),
    ],
    moduleBarTints: <Color>[
      Color(0xFF92A965),
      Color(0xFF6BB086),
      Color(0xFF4BB1AA),
      Color(0xFF52ACC9),
      Color(0xFF75A1D9),
      Color(0xFF9996D7),
      Color(0xFFB88BC4),
      Color(0xFFCC86A5),
    ],
    onModuleBlockTint: Color(0xFFF0F2F5),
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
    List<Color>? moduleTints,
    List<Color>? moduleTintsBold,
    List<Color>? moduleBlockTints,
    List<Color>? moduleSpineTints,
    List<Color>? moduleBarTints,
    Color? onModuleBlockTint,
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
    moduleTints: moduleTints ?? this.moduleTints,
    moduleTintsBold: moduleTintsBold ?? this.moduleTintsBold,
    moduleBlockTints: moduleBlockTints ?? this.moduleBlockTints,
    moduleSpineTints: moduleSpineTints ?? this.moduleSpineTints,
    moduleBarTints: moduleBarTints ?? this.moduleBarTints,
    onModuleBlockTint: onModuleBlockTint ?? this.onModuleBlockTint,
  );

  /// A categorical palette has nothing meaningful between two schemes, so a
  /// length change is a cut rather than a blend.
  static List<Color> _lerpRamp(
    List<Color> a,
    List<Color> b,
    double t,
    Color Function(Color, Color) mix,
  ) {
    if (a.length != b.length) return t < 0.5 ? a : b;
    return <Color>[for (var i = 0; i < a.length; i++) mix(a[i], b[i])];
  }

  /// Every colour role, in declaration order, for equality and hashing. The
  /// ramps are held out because a List compares by identity.
  List<Object?> get _roles => <Object?>[
    surface,
    surfaceLowest,
    surfaceContainer,
    surfaceContainerHigh,
    surfaceContainerHighest,
    outline,
    outlineVariant,
    onSurface,
    onSurfaceVariant,
    onSurfaceMuted,
    primary,
    onPrimary,
    now,
    onNow,
    nowContainer,
    attention,
    attentionContainer,
    onAttentionContainer,
    positive,
    positiveContainer,
    onPositiveContainer,
    inverseSurface,
    scrim,
    onModuleBlockTint,
  ];

  List<List<Color>> get _ramps => <List<Color>>[
    moduleTints,
    moduleTintsBold,
    moduleBlockTints,
    moduleSpineTints,
    moduleBarTints,
  ];

  /// Value equality, so a theme rebuilt with the same choice does not read as
  /// a change. Identity would make every `copyWith` a new palette.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CampusColors) return false;
    if (!listEquals(_roles, other._roles)) return false;
    final mine = _ramps;
    final theirs = other._ramps;
    for (var i = 0; i < mine.length; i++) {
      if (!listEquals(mine[i], theirs[i])) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(_roles),
    Object.hashAll(<int>[for (final ramp in _ramps) Object.hashAll(ramp)]),
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
      moduleTints: _lerpRamp(moduleTints, other.moduleTints, t, mix),
      moduleTintsBold: _lerpRamp(
        moduleTintsBold,
        other.moduleTintsBold,
        t,
        mix,
      ),
      moduleBlockTints: _lerpRamp(
        moduleBlockTints,
        other.moduleBlockTints,
        t,
        mix,
      ),
      moduleSpineTints: _lerpRamp(
        moduleSpineTints,
        other.moduleSpineTints,
        t,
        mix,
      ),
      moduleBarTints: _lerpRamp(moduleBarTints, other.moduleBarTints, t, mix),
      onModuleBlockTint: mix(onModuleBlockTint, other.onModuleBlockTint),
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
