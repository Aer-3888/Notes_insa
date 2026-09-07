import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/theme/campus_theme.dart';
import 'package:notes_insa/theme/module_tints.dart';
import 'package:notes_insa/theme/tokens.dart';

CampusColors colorsOf(
  Brightness brightness, {
  ScheduleTintScheme scheme = ScheduleTintScheme.spectre,
  ScheduleTintIntensity intensity = ScheduleTintIntensity.standard,
}) => campusTheme(
  brightness,
  scheme: scheme,
  intensity: intensity,
).extension<CampusColors>()!;

void main() {
  test('the default is exactly what shipped', () {
    final c = colorsOf(Brightness.light);
    final ramps = kLightModuleTints[ScheduleTintScheme.spectre]!;
    expect(c.moduleBlockTints, ramps.fill);
    expect(c.moduleSpineTints, ramps.fill);
    expect(c.moduleBarTints, ramps.bold);
    expect(c.onModuleBlockTint, CampusColors.light.onSurface);
  });

  test('discret leaves blocks neutral and puts bold on the spine', () {
    final c = colorsOf(
      Brightness.light,
      intensity: ScheduleTintIntensity.discret,
    );
    final ramps = kLightModuleTints[ScheduleTintScheme.spectre]!;
    expect(c.moduleBlockTints, isEmpty);
    expect(c.moduleSpineTints, ramps.bold);
    expect(c.moduleBarTints, ramps.bold);
    expect(c.onModuleBlockTint, CampusColors.light.onSurface);
  });

  test('vif fills blocks with the bold ramp and inverts the label', () {
    final c = colorsOf(Brightness.light, intensity: ScheduleTintIntensity.vif);
    final ramps = kLightModuleTints[ScheduleTintScheme.spectre]!;
    expect(c.moduleBlockTints, ramps.bold);
    expect(c.onModuleBlockTint, CampusColors.light.surfaceLowest);
  });

  test('a scheme changes which ramp is resolved', () {
    final c = colorsOf(Brightness.dark, scheme: ScheduleTintScheme.froid);
    expect(
      c.moduleBlockTints,
      kDarkModuleTints[ScheduleTintScheme.froid]!.fill,
    );
  });

  test('sans couleur empties every surface at every intensity', () {
    for (final intensity in ScheduleTintIntensity.values) {
      final c = colorsOf(
        Brightness.light,
        scheme: ScheduleTintScheme.aucune,
        intensity: intensity,
      );
      expect(c.moduleBlockTints, isEmpty, reason: intensity.name);
      expect(c.moduleSpineTints, isEmpty, reason: intensity.name);
      expect(c.moduleBarTints, isEmpty, reason: intensity.name);
    }
  });

  test('lerp between ramps of different lengths does not throw', () {
    final a = colorsOf(Brightness.light, scheme: ScheduleTintScheme.spectre);
    final b = colorsOf(Brightness.light, scheme: ScheduleTintScheme.accessible);
    // A categorical palette cannot blend, so a scheme change is a cut.
    expect(a.lerp(b, 0.5).moduleBlockTints, b.moduleBlockTints);
    expect(a.lerp(b, 0.2).moduleBlockTints, a.moduleBlockTints);
  });
}
