import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

const String kCampusFontFamily = 'PublicSans';

TextStyle _text(
  double size,
  double line,
  FontWeight weight,
  Color color, {
  double letterSpacing = 0,
  bool tabular = false,
}) => TextStyle(
  fontFamily: kCampusFontFamily,
  fontSize: size,
  height: line / size,
  fontWeight: weight,
  // Variable font: the weight axis must be driven explicitly on every
  // platform, fontWeight alone only picks among static faces.
  fontVariations: [FontVariation.weight(weight.value.toDouble())],
  letterSpacing: letterSpacing,
  color: color,
  fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
);

/// The single source of every Material default. docs/design/design-direction.md §3.
ThemeData campusTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final c = dark ? CampusColors.dark : CampusColors.light;
  final ink = c.onSurface;

  final textTheme = TextTheme(
    displayMedium: _text(
      40,
      44,
      FontWeight.w600,
      ink,
      letterSpacing: -0.5,
      tabular: true,
    ),
    headlineMedium: _text(26, 32, FontWeight.w700, ink, letterSpacing: -0.4),
    titleLarge: _text(20, 26, FontWeight.w600, ink),
    titleMedium: _text(16, 22, FontWeight.w600, ink),
    bodyLarge: _text(16, 24, FontWeight.w400, ink),
    bodyMedium: _text(14, 20, FontWeight.w400, ink),
    bodySmall: _text(12, 16, FontWeight.w500, ink),
    labelLarge: _text(14, 20, FontWeight.w600, ink),
    labelMedium: _text(12, 16, FontWeight.w500, ink),
    labelSmall: _text(12, 16, FontWeight.w500, ink),
  );

  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.primary,
    onPrimary: c.onPrimary,
    primaryContainer: c.surfaceContainerHighest,
    onPrimaryContainer: c.onSurface,
    secondary: c.onSurfaceVariant,
    onSecondary: c.surface,
    secondaryContainer: c.surfaceContainerHigh,
    onSecondaryContainer: c.onSurface,
    tertiary: c.positive,
    onTertiary: c.surface,
    tertiaryContainer: c.positiveContainer,
    onTertiaryContainer: c.onPositiveContainer,
    error: c.attention,
    onError: c.surfaceLowest,
    errorContainer: c.attentionContainer,
    onErrorContainer: c.onAttentionContainer,
    surface: c.surface,
    onSurface: c.onSurface,
    surfaceContainerLowest: c.surfaceLowest,
    surfaceContainerLow: c.surface,
    surfaceContainer: c.surfaceContainer,
    surfaceContainerHigh: c.surfaceContainerHigh,
    surfaceContainerHighest: c.surfaceContainerHighest,
    onSurfaceVariant: c.onSurfaceVariant,
    outline: c.outline,
    outlineVariant: c.outlineVariant,
    inverseSurface: c.inverseSurface,
    onInverseSurface: c.surface,
    inversePrimary: c.surfaceContainerHighest,
    scrim: c.scrim,
    shadow: const Color(0xFF000000),
    surfaceTint: c.surface,
  );

  final overlay =
      (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: c.surfaceContainer,
        systemNavigationBarIconBrightness: dark
            ? Brightness.light
            : Brightness.dark,
      );

  const controlShape = RoundedRectangleBorder(
    borderRadius: CampusRadii.controlRadius,
  );

  OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: CampusRadii.controlRadius,
        borderSide: BorderSide(color: color, width: width),
      );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: kCampusFontFamily,
    textTheme: textTheme,
    scaffoldBackgroundColor: c.surface,
    splashFactory: InkSparkle.splashFactory,
    visualDensity: VisualDensity.standard,
    extensions: <ThemeExtension<dynamic>>[
      c,
      CampusTypography(
        displayNumeral: _text(
          40,
          44,
          FontWeight.w600,
          ink,
          letterSpacing: -0.5,
          tabular: true,
        ),
        numeral: _text(16, 20, FontWeight.w600, ink, tabular: true),
      ),
    ],
    iconTheme: IconThemeData(color: c.onSurfaceVariant, size: 24),
    appBarTheme: AppBarThemeData(
      backgroundColor: c.surface,
      foregroundColor: c.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge,
      systemOverlayStyle: overlay,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.surfaceContainer,
      indicatorColor: c.now,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      height: 80,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? c.onNow
              : c.onSurfaceVariant,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => textTheme.labelMedium!.copyWith(
          color: states.contains(WidgetState.selected)
              ? c.onSurface
              : c.onSurfaceVariant,
        ),
      ),
    ),
    cardTheme: CardThemeData(
      color: dark ? c.surfaceContainer : c.surfaceLowest,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(borderRadius: CampusRadii.cardRadius),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: c.surfaceContainerHighest,
      selectedColor: c.now,
      disabledColor: c.surfaceContainer,
      labelStyle: textTheme.labelMedium,
      secondaryLabelStyle: textTheme.labelMedium!.copyWith(color: c.onNow),
      side: BorderSide.none,
      shape: controlShape,
      showCheckmark: false,
      iconTheme: IconThemeData(color: c.onSurfaceVariant, size: 18),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: c.now,
        selectedForegroundColor: c.onNow,
        backgroundColor: c.surfaceContainer,
        foregroundColor: c.onSurface,
        side: BorderSide.none,
        shape: controlShape,
        textStyle: textTheme.labelLarge,
      ),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: dark ? c.surfaceContainer : c.surfaceLowest,
      hintStyle: textTheme.bodyLarge!.copyWith(color: c.onSurfaceMuted),
      labelStyle: textTheme.bodyMedium!.copyWith(color: c.onSurfaceVariant),
      helperStyle: textTheme.bodySmall!.copyWith(color: c.onSurfaceVariant),
      errorStyle: textTheme.bodySmall!.copyWith(color: c.attention),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: CampusSpacing.x4,
        vertical: 14,
      ),
      border: inputBorder(c.outline),
      enabledBorder: inputBorder(c.outline),
      focusedBorder: inputBorder(c.primary, 2),
      errorBorder: inputBorder(c.attention),
      focusedErrorBorder: inputBorder(c.attention, 2),
    ),
    // Colours come from the scheme so FilledButton stays ink and
    // FilledButton.tonal stays neutral; only geometry is set here.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(
          CampusSpacing.touchTarget,
          CampusSpacing.touchTarget,
        ),
        padding: const EdgeInsets.symmetric(horizontal: CampusSpacing.x5),
        shape: controlShape,
        textStyle: textTheme.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.onSurface,
        minimumSize: const Size(
          CampusSpacing.touchTarget,
          CampusSpacing.touchTarget,
        ),
        shape: controlShape,
        textStyle: textTheme.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.onSurface,
        side: BorderSide(color: c.outline),
        minimumSize: const Size(
          CampusSpacing.touchTarget,
          CampusSpacing.touchTarget,
        ),
        shape: controlShape,
        textStyle: textTheme.labelLarge,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surfaceContainerHigh,
      modalBackgroundColor: c.surfaceContainerHigh,
      elevation: 0,
      modalElevation: 0,
      showDragHandle: true,
      dragHandleColor: c.outline,
      shape: const RoundedRectangleBorder(
        borderRadius: CampusRadii.sheetRadius,
      ),
      clipBehavior: Clip.antiAlias,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surfaceContainerHigh,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(CampusRadii.sheet)),
      ),
      titleTextStyle: textTheme.titleLarge,
      contentTextStyle: textTheme.bodyLarge,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.inverseSurface,
      contentTextStyle: textTheme.bodyMedium!.copyWith(color: c.surface),
      behavior: SnackBarBehavior.floating,
      shape: controlShape,
      actionTextColor: c.now,
      elevation: 3,
    ),
    dividerTheme: DividerThemeData(
      color: c.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    listTileTheme: ListTileThemeData(
      minVerticalPadding: CampusSpacing.x3,
      iconColor: c.onSurfaceVariant,
      textColor: c.onSurface,
      titleTextStyle: textTheme.bodyLarge,
      subtitleTextStyle: textTheme.bodyMedium!.copyWith(
        color: c.onSurfaceVariant,
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: CampusSpacing.gutter,
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStatePropertyAll(dark ? c.onSurface : c.surfaceLowest),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? c.positive
            : c.surfaceContainerHighest,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: c.onSurface,
      linearTrackColor: c.surfaceContainerHighest,
      circularTrackColor: c.surfaceContainerHighest,
    ),
    bannerTheme: MaterialBannerThemeData(
      backgroundColor: c.surfaceContainer,
      contentTextStyle: textTheme.bodyMedium,
      padding: const EdgeInsets.fromLTRB(
        CampusSpacing.gutter,
        CampusSpacing.x2,
        CampusSpacing.x2,
        CampusSpacing.x2,
      ),
    ),
    badgeTheme: BadgeThemeData(
      backgroundColor: c.now,
      textColor: c.onNow,
      textStyle: textTheme.labelSmall,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}
