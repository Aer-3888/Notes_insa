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

/// Location labels whose building is explicit in the official campus plan,
/// but whose ADE spelling is shorter than the public place name.
const Map<String, String> _verifiedAliases = <String, String>{
  'departement stpi': '2',
  'departement eii': '10',
  'departement gcu': '7',
  'departement gma': '11',
  'departement info': '18',
  'departement src': '6',
  'humanites': '6',
};

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

  final alias = _verifiedAliases[name];
  if (alias != null) return ResolvedRoom(raw: text, buildingCode: alias);

  // The INFO department has a campus-wide room prefix. The official rentrée
  // information also writes these as "INF-016, bâtiment 18".
  if (name.startsWith('inf-')) {
    return ResolvedRoom(raw: text, buildingCode: '18');
  }

  for (final place in places) {
    if (foldForSearch(place.name) == name) {
      return ResolvedRoom(raw: text, place: place, buildingCode: place.code);
    }
  }
  return ResolvedRoom(raw: text);
}
