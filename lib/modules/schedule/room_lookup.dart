import 'package:flutter/foundation.dart';

import '../campus_map/campus_places.dart';

/// A room string from ADE, resolved to a building when we can manage it.
///
/// Most rooms do not resolve: the feed is full of starred room numbers with
/// no building in them. [raw] is always shown; the map action appears only
/// when [isResolved].
@immutable
class ResolvedRoom {
  const ResolvedRoom({required this.raw, this.place, this.buildingCode});

  /// Exactly what ADE gave us, for display.
  final String raw;

  /// Set only when the room matched a named place.
  final CampusPlace? place;

  /// Building number on the INSA plan.
  final String? buildingCode;

  bool get isResolved => buildingCode != null;

  /// What to pre-fill the Carte search with. The place name when we have one,
  /// because it is what a student recognises; the building number otherwise.
  String? get mapQuery => place?.name ?? buildingCode;
}

/// `bat 6`, `bât. 12`, case-insensitive.
final RegExp _building = RegExp(r'b[aâ]t\.?\s*(\d+)', caseSensitive: false);

ResolvedRoom resolveRoom(String? raw, List<CampusPlace> places) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) return ResolvedRoom(raw: text);

  // A room that names its own building needs no lookup, and is more reliable
  // than one: "Salle TP 2 A (115)-bat 6".
  final stated = _building.firstMatch(text);
  if (stated != null) {
    return ResolvedRoom(raw: text, buildingCode: stated.group(1));
  }

  // Everything before the first parenthesis. ADE appends a site marker, and
  // sometimes trailing text after it, so cutting at "(" beats stripping a
  // trailing group.
  final name = foldForSearch(text.split('(').first);
  if (name.isEmpty) return ResolvedRoom(raw: text);

  for (final place in places) {
    if (foldForSearch(place.name) == name) {
      return ResolvedRoom(raw: text, place: place, buildingCode: place.code);
    }
  }
  return ResolvedRoom(raw: text);
}
