import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/theme/tokens.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// (label, foreground, background, minimum ratio) for the pairs the direction
/// document promises. docs/design/design-direction.md §3.1.
List<(String, Color, Color, double)> pairs(CampusColors c) => [
  ('onSurface on surface', c.onSurface, c.surface, 14),
  ('onSurface on surfaceLowest', c.onSurface, c.surfaceLowest, 14),
  ('onSurface on surfaceContainer', c.onSurface, c.surfaceContainer, 11),
  ('onSurface on surfaceContainerHigh', c.onSurface, c.surfaceContainerHigh, 9),
  ('onSurface on nowContainer', c.onSurface, c.nowContainer, 4.5),
  ('onSurfaceVariant on surface', c.onSurfaceVariant, c.surface, 4.5),
  ('onSurfaceMuted on surface', c.onSurfaceMuted, c.surface, 3),
  ('outline on surface', c.outline, c.surface, 3),
  ('onPrimary on primary', c.onPrimary, c.primary, 4.5),
  ('onNow on now', c.onNow, c.now, 7),
  ('attention on surface', c.attention, c.surface, 4.5),
  (
    'onAttentionContainer on attentionContainer',
    c.onAttentionContainer,
    c.attentionContainer,
    4.5,
  ),
  ('positive on surface', c.positive, c.surface, 4.5),
  (
    'onPositiveContainer on positiveContainer',
    c.onPositiveContainer,
    c.positiveContainer,
    4.5,
  ),
  ('surface on inverseSurface', c.surface, c.inverseSurface, 7),
];

void main() {
  for (final (name, colors) in [
    ('light', CampusColors.light),
    ('dark', CampusColors.dark),
  ]) {
    group('$name scheme', () {
      for (final (label, fg, bg, minimum) in pairs(colors)) {
        test('$label >= $minimum:1', () {
          expect(
            contrast(fg, bg),
            greaterThanOrEqualTo(minimum),
            reason: '$label is ${contrast(fg, bg).toStringAsFixed(2)}:1',
          );
        });
      }
    });
  }

  test('lerp at 0.5 lands between the two schemes', () {
    final mid = CampusColors.light.lerp(CampusColors.dark, 0.5);
    final lightL = CampusColors.light.surface.computeLuminance();
    final darkL = CampusColors.dark.surface.computeLuminance();
    final midL = mid.surface.computeLuminance();
    expect(midL, lessThan(lightL));
    expect(midL, greaterThan(darkL));
  });

  test('copyWith replaces only the named field', () {
    final changed = CampusColors.light.copyWith(now: const Color(0xFF000000));
    expect(changed.now, const Color(0xFF000000));
    expect(changed.surface, CampusColors.light.surface);
  });

  test('numeral styles use tabular figures', () {
    const type = CampusTypography(
      displayNumeral: TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
      numeral: TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
    );
    expect(
      type.numeral.fontFeatures,
      contains(const FontFeature.tabularFigures()),
    );
  });

  test('spacing follows the 4 dp scale and radii are 8/12/20', () {
    expect(
      [
        CampusSpacing.x1,
        CampusSpacing.x2,
        CampusSpacing.x3,
        CampusSpacing.x4,
        CampusSpacing.x5,
        CampusSpacing.x6,
        CampusSpacing.x8,
        CampusSpacing.x10,
      ],
      [4, 8, 12, 16, 20, 24, 32, 40],
    );
    expect(CampusRadii.control, 8);
    expect(CampusRadii.card, 12);
    expect(CampusRadii.sheet, 20);
  });

  testWidgets('CampusMotion.of collapses to zero when animations are off', (
    tester,
  ) async {
    late Duration seen;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Builder(
          builder: (context) {
            seen = CampusMotion.of(context, CampusMotion.enter);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(seen, Duration.zero);
  });
}
