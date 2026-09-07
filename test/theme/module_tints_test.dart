import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/theme/module_tints.dart';
import 'package:notes_insa/theme/tokens.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

double _toLinear(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _fromLinear(double c) => c <= 0.0031308
    ? c * 12.92
    : 1.055 * math.pow(c, 1 / 2.4).toDouble() - 0.055;

/// Viénot 1999 dichromacy simulation, in linear sRGB via Hunt-Pointer-Estevez
/// LMS. Test-only: nothing in lib/ simulates colour vision. The LMS matrix is
/// the classic 0-255 formulation, but it is applied with its own inverse, so
/// the scale cancels and working in 0-1 is exact.
const List<List<double>> _rgbToLms = <List<double>>[
  <double>[17.8824, 43.5161, 4.11935],
  <double>[3.45565, 27.1554, 3.86714],
  <double>[0.0299566, 0.184309, 1.46709],
];
const List<List<double>> _lmsToRgb = <List<double>>[
  <double>[0.080944448, -0.130504409, 0.116721066],
  <double>[-0.010248534, 0.054019327, -0.113614708],
  <double>[-0.000365297, -0.004121615, 0.693511405],
];
const List<List<double>> _protanopia = <List<double>>[
  <double>[0, 2.02344, -2.52581],
  <double>[0, 1, 0],
  <double>[0, 0, 1],
];
const List<List<double>> _deuteranopia = <List<double>>[
  <double>[1, 0, 0],
  <double>[0.494207, 0, 1.24827],
  <double>[0, 0, 1],
];

List<double> _apply(List<List<double>> m, List<double> v) => <double>[
  for (var i = 0; i < 3; i++) m[i][0] * v[0] + m[i][1] * v[1] + m[i][2] * v[2],
];

Color simulate(Color c, List<List<double>> deficiency) {
  final linear = <double>[_toLinear(c.r), _toLinear(c.g), _toLinear(c.b)];
  final out = _apply(_lmsToRgb, _apply(deficiency, _apply(_rgbToLms, linear)));
  return Color.from(
    alpha: 1,
    red: _fromLinear(out[0].clamp(0.0, 1.0)),
    green: _fromLinear(out[1].clamp(0.0, 1.0)),
    blue: _fromLinear(out[2].clamp(0.0, 1.0)),
  );
}

/// OKLab, so "how far apart do these look" is measured in a space built for
/// the question. The separation thresholds below are in OKLab units.
List<double> _oklab(Color c) {
  final r = _toLinear(c.r);
  final g = _toLinear(c.g);
  final b = _toLinear(c.b);
  double cbrt(double v) => math.pow(v, 1 / 3).toDouble();
  final l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
  final m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
  final s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
  return <double>[
    0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
    1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
    0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
  ];
}

double distance(Color a, Color b) {
  final x = _oklab(a);
  final y = _oklab(b);
  return math.sqrt(
    math.pow(x[0] - y[0], 2) +
        math.pow(x[1] - y[1], 2) +
        math.pow(x[2] - y[2], 2),
  );
}

/// The worst-separated pair in a ramp, across both dichromacies.
double worstPair(List<Color> ramp) {
  var worst = double.infinity;
  for (final deficiency in <List<List<double>>>[_protanopia, _deuteranopia]) {
    for (var i = 0; i < ramp.length; i++) {
      for (var j = i + 1; j < ramp.length; j++) {
        final gap = distance(
          simulate(ramp[i], deficiency),
          simulate(ramp[j], deficiency),
        );
        if (gap < worst) worst = gap;
      }
    }
  }
  return worst;
}

void main() {
  final cases =
      <(String, CampusColors, Map<ScheduleTintScheme, ModuleTintRamps>, Color)>[
        (
          'light',
          CampusColors.light,
          kLightModuleTints,
          CampusColors.light.surfaceLowest,
        ),
        (
          'dark',
          CampusColors.dark,
          kDarkModuleTints,
          CampusColors.dark.surfaceLowest,
        ),
      ];

  // How many tints each scheme promises. Accessible is four because lightness,
  // not hue, carries separation for a dichromat.
  const lengths = <ScheduleTintScheme, int>{
    ScheduleTintScheme.spectre: 8,
    ScheduleTintScheme.froid: 8,
    ScheduleTintScheme.accessible: 4,
    ScheduleTintScheme.aucune: 0,
  };

  for (final (mode, colors, table, vifInk) in cases) {
    group('$mode ramps', () {
      test('every scheme is in the table', () {
        expect(table.keys.toSet(), ScheduleTintScheme.values.toSet());
      });

      for (final scheme in ScheduleTintScheme.values) {
        final ramps = table[scheme]!;

        test('${scheme.name} has the promised length', () {
          expect(ramps.fill, hasLength(lengths[scheme]));
          expect(ramps.bold, hasLength(ramps.fill.length));
        });

        for (var i = 0; i < lengths[scheme]!; i++) {
          test('${scheme.name} fill $i carries onSurface text', () {
            expect(
              contrast(colors.onSurface, ramps.fill[i]),
              greaterThanOrEqualTo(4.5),
            );
          });

          test('${scheme.name} bold $i reads against the surface', () {
            expect(
              contrast(ramps.bold[i], colors.surface),
              greaterThanOrEqualTo(4.5),
            );
          });

          test('${scheme.name} bold $i carries the Vif label ink', () {
            expect(contrast(vifInk, ramps.bold[i]), greaterThanOrEqualTo(4.5));
          });

          test('${scheme.name} tint $i keeps clear of the now accent', () {
            final accent = HSLColor.fromColor(colors.now).hue;
            final hue = HSLColor.fromColor(ramps.fill[i]).hue;
            final gap = (hue - accent).abs();
            expect(math.min(gap, 360 - gap), greaterThan(30));
          });

          test('${scheme.name} bold $i keeps the hue of its fill', () {
            final fill = HSLColor.fromColor(ramps.fill[i]).hue;
            final bold = HSLColor.fromColor(ramps.bold[i]).hue;
            final gap = (fill - bold).abs();
            expect(math.min(gap, 360 - gap), lessThan(25));
          });
        }

        // Spectre and Froid are one weight so blocks read evenly. Accessible
        // deliberately is not: see the spec, "The one invariant that bends".
        if (scheme == ScheduleTintScheme.spectre ||
            scheme == ScheduleTintScheme.froid) {
          test('${scheme.name} fills carry the weight of a block fill', () {
            final reference = contrast(
              colors.surfaceContainerHighest,
              colors.surface,
            );
            for (final tint in ramps.fill) {
              expect(contrast(tint, colors.surface), closeTo(reference, 0.15));
            }
          });
        }
      }

      test('accessible fills step from 1.25 to 2.60 against the surface', () {
        final ratios = <double>[
          for (final c in table[ScheduleTintScheme.accessible]!.fill)
            contrast(c, colors.surface),
        ];
        expect(ratios.first, closeTo(1.25, 0.05));
        expect(ratios.last, closeTo(2.60, 0.05));
        for (var i = 1; i < ratios.length; i++) {
          expect(ratios[i] - ratios[i - 1], greaterThan(0.30));
        }
      });

      test('accessible stays separable under protanopia and deuteranopia', () {
        final spectre = table[ScheduleTintScheme.spectre]!;
        final accessible = table[ScheduleTintScheme.accessible]!;

        // Two claims. The absolute one is the point of the scheme: measured
        // 2026-09-07, the worst pair of every Accessible ramp is at least
        // 0.045 in OKLab, above the margin at which two large fields are
        // reliably told apart. The comparative one keeps the improvement
        // honest if the default scheme is ever retuned; measured ratios were
        // 8.6x to 18.3x, so a floor of 4x leaves room without hiding a
        // regression.
        expect(worstPair(accessible.fill), greaterThan(0.040));
        expect(worstPair(accessible.bold), greaterThan(0.040));
        expect(
          worstPair(accessible.fill),
          greaterThan(worstPair(spectre.fill) * 4),
        );
        expect(
          worstPair(accessible.bold),
          greaterThan(worstPair(spectre.bold) * 4),
        );
      });
    });
  }

  test('aucune supplies no tints at all', () {
    expect(kLightModuleTints[ScheduleTintScheme.aucune]!.fill, isEmpty);
    expect(kDarkModuleTints[ScheduleTintScheme.aucune]!.bold, isEmpty);
  });

  test('every scheme and intensity names itself in French', () {
    for (final s in ScheduleTintScheme.values) {
      expect(s.label, isNotEmpty);
      expect(s.description, isNotEmpty);
    }
    for (final i in ScheduleTintIntensity.values) {
      expect(i.label, isNotEmpty);
      expect(i.description, isNotEmpty);
    }
  });
}
