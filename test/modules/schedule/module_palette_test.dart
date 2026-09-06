import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/modules/schedule/module_palette.dart';
import 'package:notes_insa/modules/schedule/schedule_event.dart';

ScheduleEvent _event(String title, {String? module}) => ScheduleEvent(
  title: title,
  start: DateTime(2026, 9, 7, 8),
  end: DateTime(2026, 9, 7, 10),
  groups: const <String>[],
  teachers: const <String>[],
  module: module,
);

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

  group('rank', () {
    test('orders modules by how often they occur', () {
      final ranked = ModulePalette.rank(<ScheduleEvent>[
        _event('PHYSIQUE_L'),
        _event('Analyse 3_GHIJKL'),
        _event('Analyse 3_GHIJKL'),
        _event('Analyse 3_GHIJKL'),
        _event('PHYSIQUE_L'),
        _event('EPS_CDEFL'),
      ]);
      expect(ranked, <String>['analyse 3', 'physique', 'eps']);
    });

    test('prefers the module field over the dirty summary', () {
      final ranked = ModulePalette.rank(<ScheduleEvent>[
        _event('Algèbre 3 - GHIJKL', module: 'Algebre 3 (Algebra)'),
      ]);
      expect(ranked, <String>['algebre 3']);
    });

    test('ties break alphabetically so the order is stable', () {
      final ranked = ModulePalette.rank(<ScheduleEvent>[
        _event('ZZZ_L'),
        _event('AAA_L'),
      ]);
      expect(ranked, <String>['aaa', 'zzz']);
    });
  });

  group('colorFor', () {
    test('an empty palette always yields the fallback', () {
      final palette = ModulePalette(tints: const <Color>[]);
      expect(
        palette.colorFor('analyse 3', fallback: const Color(0xFF123456)),
        const Color(0xFF123456),
      );
    });

    test('ranked modules take tints in order, the rest fall back', () {
      const a = Color(0xFF000001);
      const b = Color(0xFF000002);
      const fallback = Color(0xFF999999);
      final palette = ModulePalette(
        tints: const <Color>[a, b],
        ranked: const <String>['analyse 3', 'physique', 'eps'],
      );
      expect(palette.colorFor('analyse 3', fallback: fallback), a);
      expect(palette.colorFor('physique', fallback: fallback), b);
      expect(palette.colorFor('eps', fallback: fallback), fallback);
    });

    test('two palettes do not share ranking state', () {
      const fallback = Color(0xFF999999);
      final first = ModulePalette(
        tints: const <Color>[Color(0xFF000001)],
        ranked: const <String>['analyse 3'],
      );
      final second = ModulePalette(tints: const <Color>[Color(0xFF000001)]);
      expect(first.colorFor('analyse 3', fallback: fallback), isNot(fallback));
      expect(second.colorFor('analyse 3', fallback: fallback), fallback);
    });
  });
}
