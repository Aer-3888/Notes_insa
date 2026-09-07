import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/modules/schedule/module_palette.dart';
import 'package:notes_insa/theme/tokens.dart';

void main() {
  group('normalize', () {
    test('strips the group suffix ADE glues onto the summary', () {
      expect(ModulePalette.normalize('Algèbre 3 - GHIJKL'), 'algèbre 3');
      expect(ModulePalette.normalize('Analyse 3_GHIJKL'), 'analyse 3');
      expect(ModulePalette.normalize('PHYSIQUE_L'), 'physique');
      expect(ModulePalette.normalize('EPS_CDEFL'), 'eps');
    });

    test('strips a trailing parenthetical translation', () {
      expect(ModulePalette.normalize('Algebre 3 (Algebra)'), 'algebre 3');
    });

    test('collapses whitespace and casefolds', () {
      expect(ModulePalette.normalize('  CULTURE  &  COM_L '), 'culture & com');
    });

    test('leaves a name with no suffix alone', () {
      expect(ModulePalette.normalize('Analyse 3'), 'analyse 3');
    });
  });

  group('colorFor', () {
    const tints = <Color>[
      Color(0xFF000001),
      Color(0xFF000002),
      Color(0xFF000003),
      Color(0xFF000004),
    ];
    const fallback = Color(0xFF999999);

    test('an empty palette always yields the fallback', () {
      const palette = ModulePalette(tints: <Color>[]);
      expect(palette.colorFor('analyse 3', fallback: fallback), fallback);
    });

    test('an empty key yields the fallback', () {
      const palette = ModulePalette(tints: tints);
      expect(palette.colorFor('', fallback: fallback), fallback);
    });

    test('the same key always yields the same tint', () {
      const palette = ModulePalette(tints: tints);
      expect(
        palette.colorFor('analyse 3', fallback: fallback),
        palette.colorFor('analyse 3', fallback: fallback),
      );
    });

    test('two palettes agree, so a colour survives a rebuild', () {
      const first = ModulePalette(tints: tints);
      const second = ModulePalette(tints: tints);
      for (final key in <String>['analyse 3', 'physique', 'eps', 'lv1']) {
        expect(
          first.colorFor(key, fallback: fallback),
          second.colorFor(key, fallback: fallback),
        );
      }
    });

    test('the tint does not depend on which other modules exist', () {
      // The whole point of hashing over ranking: swiping to a week where
      // Analyse does not appear must not repaint Physique.
      const palette = ModulePalette(tints: tints);
      final physique = palette.colorFor('physique', fallback: fallback);
      expect(palette.colorFor('physique', fallback: fallback), physique);
    });

    test('a group suffix does not split one module across two tints', () {
      const palette = ModulePalette(tints: tints);
      expect(
        palette.colorFor(
          ModulePalette.normalize('Analyse 3_GHIJKL'),
          fallback: fallback,
        ),
        palette.colorFor(
          ModulePalette.normalize('Analyse 3'),
          fallback: fallback,
        ),
      );
    });

    test('every tint is reachable', () {
      const palette = ModulePalette(tints: tints);
      final seen = <Color>{
        for (var i = 0; i < 200; i++)
          palette.colorFor('module $i', fallback: fallback),
      };
      expect(seen, hasLength(tints.length));
    });

    test('the shipped tints spread a realistic semester', () {
      // A dozen modules over eight tints collide by pigeonhole; what matters
      // is that the spread is not degenerate.
      final palette = ModulePalette(tints: CampusColors.light.moduleTints);
      const modules = <String>[
        'analyse 3',
        'algèbre 3',
        'physique',
        'eps',
        'lv1 anglais',
        'culture & com',
        'informatique',
        'électronique',
        'mécanique',
        'projet',
        'mathématiques appliquées',
        'thermodynamique',
      ];
      final seen = <Color>{
        for (final m in modules) palette.colorFor(m, fallback: fallback),
      };
      expect(seen.length, greaterThanOrEqualTo(5));
    });
  });
}
