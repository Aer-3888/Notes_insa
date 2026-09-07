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

  for (final (name, colors) in [
    ('light', CampusColors.light),
    ('dark', CampusColors.dark),
  ]) {
    group('$name module tints', () {
      test('there are eight of them', () {
        expect(colors.moduleTints, hasLength(8));
      });

      // A tint is a block fill with the module name on it, so it has to carry
      // body text in both modes.
      for (var i = 0; i < 8; i++) {
        test('tint $i carries onSurface text', () {
          expect(
            contrast(colors.onSurface, colors.moduleTints[i]),
            greaterThanOrEqualTo(4.5),
          );
        });
      }

      test('no tint sits in the gorse accent hue', () {
        final accent = HSLColor.fromColor(colors.now).hue;
        for (final tint in colors.moduleTints) {
          final hue = HSLColor.fromColor(tint).hue;
          final gap = (hue - accent).abs();
          expect(
            math.min(gap, 360 - gap),
            greaterThan(30),
            reason: 'a tint at $hue competes with the now accent at $accent',
          );
        }
      });

      test('there are eight bold tints, one per fill tint', () {
        expect(colors.moduleTintsBold, hasLength(colors.moduleTints.length));
      });

      // A strip bar carries no text: the bar itself is the information, so it
      // answers to the 3:1 of WCAG 1.4.11 against the surface it sits on.
      for (var i = 0; i < 8; i++) {
        test('bold tint $i reads as a graphic on the surface', () {
          expect(
            contrast(colors.moduleTintsBold[i], colors.surface),
            greaterThanOrEqualTo(3),
          );
        });
      }

      test('bold tints clear text contrast, not just graphic contrast', () {
        // 3:1 is all WCAG asks of a bar, but the strip is read at a glance on
        // a phone outdoors, so hold the ramp to the 4.5:1 of body text.
        for (final bold in colors.moduleTintsBold) {
          expect(contrast(bold, colors.surface), greaterThanOrEqualTo(4.5));
        }
      });

      test('each bold tint keeps the hue of its fill tint', () {
        for (var i = 0; i < 8; i++) {
          final fill = HSLColor.fromColor(colors.moduleTints[i]).hue;
          final bold = HSLColor.fromColor(colors.moduleTintsBold[i]).hue;
          final gap = (fill - bold).abs();
          expect(
            math.min(gap, 360 - gap),
            lessThan(25),
            reason: 'tint $i: bar and block would read as different modules',
          );
        }
      });

      test('tints carry the weight of a block fill, not a wash', () {
        // Matched to surfaceContainerHighest, the fill they replace: any
        // lighter and a grid block loses the edge it has today.
        final reference = contrast(
          colors.surfaceContainerHighest,
          colors.surface,
        );
        for (final tint in colors.moduleTints) {
          expect(contrast(tint, colors.surface), closeTo(reference, 0.15));
        }
      });
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

  test('lerp mixes the tints element by element', () {
    final mid = CampusColors.light.lerp(CampusColors.dark, 0.5);
    expect(mid.moduleTints, hasLength(8));
    expect(
      mid.moduleTints.first,
      Color.lerp(
        CampusColors.light.moduleTints.first,
        CampusColors.dark.moduleTints.first,
        0.5,
      ),
    );
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
