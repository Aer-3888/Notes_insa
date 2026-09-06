import 'package:flutter/material.dart';

import 'schedule_event.dart';

/// Maps a module to a bar tint for the week strip.
///
/// Assignment is by frequency, not by hash: with a dozen modules a semester a
/// hash eventually gives two regulars the same colour, which is exactly the
/// case the colour exists to serve.
class ModulePalette {
  ModulePalette({required this.tints, List<String> ranked = const <String>[]})
    : _rankOf = <String, int>{
        for (var i = 0; i < ranked.length; i++) ranked[i]: i,
      };

  final List<Color> tints;

  /// Rank per normalised module key, fixed at construction. An instance field
  /// rather than static state, so two palettes cannot contaminate each other.
  final Map<String, int> _rankOf;

  Color colorFor(String key, {required Color fallback}) {
    final rank = _rankOf[key];
    if (rank == null || rank >= tints.length) return fallback;
    return tints[rank];
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

  /// Normalised module keys, most frequent first, ties alphabetical.
  static List<String> rank(List<ScheduleEvent> events) {
    final counts = <String, int>{};
    for (final event in events) {
      final key = normalize(event.module ?? event.title);
      if (key.isEmpty) continue;
      counts[key] = (counts[key] ?? 0) + 1;
    }
    final keys = counts.keys.toList();
    keys.sort((a, b) {
      final byCount = counts[b]!.compareTo(counts[a]!);
      return byCount != 0 ? byCount : a.compareTo(b);
    });
    return keys;
  }
}
