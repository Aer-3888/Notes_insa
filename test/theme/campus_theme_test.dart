import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/theme/campus_context.dart';
import 'package:notes_insa/theme/campus_theme.dart';
import 'package:notes_insa/theme/tokens.dart';

void main() {
  for (final brightness in Brightness.values) {
    group('$brightness', () {
      final theme = campusTheme(brightness);
      final tokens = brightness == Brightness.dark
          ? CampusColors.dark
          : CampusColors.light;

      test('uses Material 3 and the bundled typeface', () {
        expect(theme.useMaterial3, isTrue);
        expect(theme.textTheme.bodyLarge?.fontFamily, kCampusFontFamily);
        expect(theme.colorScheme.brightness, brightness);
      });

      test('exposes the token extensions', () {
        expect(theme.extension<CampusColors>(), tokens);
        expect(theme.extension<CampusTypography>(), isNotNull);
      });

      test('maps the scheme from the tokens', () {
        expect(theme.colorScheme.primary, tokens.primary);
        expect(theme.colorScheme.surface, tokens.surface);
        expect(theme.colorScheme.error, tokens.attention);
        expect(theme.colorScheme.errorContainer, tokens.attentionContainer);
        expect(theme.colorScheme.outlineVariant, tokens.outlineVariant);
        expect(theme.scaffoldBackgroundColor, tokens.surface);
      });

      test('the accent is not on any general-purpose scheme role', () {
        final scheme = theme.colorScheme;
        for (final role in [
          scheme.primary,
          scheme.primaryContainer,
          scheme.secondary,
          scheme.secondaryContainer,
          scheme.tertiary,
          scheme.tertiaryContainer,
          scheme.surfaceTint,
        ]) {
          expect(role, isNot(tokens.now));
        }
      });

      test('selection components carry the accent', () {
        expect(theme.navigationBarTheme.indicatorColor, tokens.now);
        expect(theme.chipTheme.selectedColor, tokens.now);
        expect(theme.badgeTheme.backgroundColor, tokens.now);
        expect(
          theme.navigationBarTheme.labelBehavior,
          NavigationDestinationLabelBehavior.alwaysShow,
        );
      });

      test('no text role is below 12 and bold is only the headline', () {
        final styles = [
          theme.textTheme.displayMedium,
          theme.textTheme.headlineMedium,
          theme.textTheme.titleLarge,
          theme.textTheme.titleMedium,
          theme.textTheme.bodyLarge,
          theme.textTheme.bodyMedium,
          theme.textTheme.bodySmall,
          theme.textTheme.labelLarge,
          theme.textTheme.labelMedium,
          theme.textTheme.labelSmall,
        ];
        for (final s in styles) {
          expect(s?.fontSize, greaterThanOrEqualTo(12));
        }
        expect(theme.textTheme.headlineMedium?.fontWeight, FontWeight.w700);
        expect(theme.textTheme.titleLarge?.fontWeight, FontWeight.w600);
      });

      test('surfaces carry no elevation and the sheet has a drag handle', () {
        expect(theme.appBarTheme.elevation, 0);
        expect(theme.appBarTheme.scrolledUnderElevation, 0);
        expect(theme.cardTheme.elevation, 0);
        expect(theme.bottomSheetTheme.showDragHandle, isTrue);
        expect(
          theme.bottomSheetTheme.backgroundColor,
          tokens.surfaceContainerHigh,
        );
        expect(theme.bottomSheetTheme.dragHandleColor, tokens.onSurfaceVariant);
      });
    });
  }

  testWidgets('the context extension resolves the same objects', (
    tester,
  ) async {
    late CampusColors seen;
    late TextStyle numeral;
    await tester.pumpWidget(
      MaterialApp(
        theme: campusTheme(Brightness.light),
        home: Builder(
          builder: (context) {
            seen = context.campus;
            numeral = context.campusType.numeral;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(seen, CampusColors.light);
    expect(numeral.fontFeatures, contains(const FontFeature.tabularFigures()));
  });
}
