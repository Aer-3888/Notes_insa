import 'package:flutter/material.dart';

import '../../theme/campus_context.dart';

/// Maps a module to a block tint.
///
/// Assignment is by hash of the normalised name, so a module keeps its colour
/// across weeks, periods and launches. With eight tints and a dozen modules a
/// semester two of them will share one; the colour is a recall aid and the
/// name on the block is what identifies it.
class ModulePalette {
  const ModulePalette({required this.tints});

  /// Grid block fills, where text sits on the tint.
  factory ModulePalette.blocksOf(BuildContext context) =>
      ModulePalette(tints: context.campus.moduleBlockTints);

  /// The 3 dp spine on a timeline row.
  factory ModulePalette.spinesOf(BuildContext context) =>
      ModulePalette(tints: context.campus.moduleSpineTints);

  /// Week strip bars, where the bar carries the information itself and a
  /// fill-weight tint would all but vanish against the surface.
  factory ModulePalette.barsOf(BuildContext context) =>
      ModulePalette(tints: context.campus.moduleBarTints);

  final List<Color> tints;

  Color colorFor(String key, {required Color fallback}) {
    if (tints.isEmpty || key.isEmpty) return fallback;
    return tints[_hash(key) % tints.length];
  }

  /// FNV-1a. Dart's `String.hashCode` is not guaranteed stable between runs,
  /// which would repaint the whole timetable on a cold start.
  static int _hash(String key) {
    var hash = 0x811c9dc5;
    for (final unit in key.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }

  /// Group suffixes ADE glues onto SUMMARY: a separator then capitals only.
  static final RegExp _groupSuffix = RegExp(r'[\s_-]+[A-Z]{1,10}$');
  static final RegExp _parenthetical = RegExp(r'\s*\([^)]*\)\s*$');
  static final RegExp _whitespace = RegExp(r'\s+');

  static String normalize(String raw) {
    var v = raw.trim();
    v = v.replaceAll(_parenthetical, '');
    v = v.replaceAll(_groupSuffix, '');
    v = v.replaceAll(_whitespace, ' ');
    return v.trim().toLowerCase();
  }
}
