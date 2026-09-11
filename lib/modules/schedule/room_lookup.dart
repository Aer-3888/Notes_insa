import 'package:flutter/foundation.dart';

import '../campus_map/campus_places.dart';

/// A room string from ADE, resolved to a building when we can manage it.
///
/// [raw] is always shown. The map action appears only when [isResolved], and
/// is suppressed for [isRemote] sessions, which have no door to walk to.
@immutable
class ResolvedRoom {
  const ResolvedRoom({
    required this.raw,
    this.place,
    this.buildingCode,
    this.isRemote = false,
  });

  /// Exactly what ADE gave us, for display.
  final String raw;

  /// Set only when the room matched a named place.
  final CampusPlace? place;

  /// Building number on the INSA plan.
  final String? buildingCode;

  /// Online or off-campus session: zoom, Moodle, teaching outside INSA.
  final bool isRemote;

  bool get isResolved => buildingCode != null;

  /// What to pre-fill the Carte search with. The place name when we have one,
  /// because it is what a student recognises; the building number otherwise.
  String? get mapQuery => place?.name ?? buildingCode;
}

/// `bat 6`, `bât. 12`, case-insensitive.
final RegExp _building = RegExp(r'b[aâ]t\.?\s*(\d+)', caseSensitive: false);

/// A central-pool room: `*111 (VPI)`, `*223* (V)`, `*114* (V)co-modal`.
///
/// These carry no building of their own. Building 2 is inferred, and the
/// evidence is worth writing down because the feed never states it:
///   - the pool is booked by every department, so it is central teaching
///     space rather than any one department's rooms;
///   - its numbers collide with rooms in buildings 5, 6 and 9 (102, 106, 110,
///     114, 117, 125, 129, 131), so it cannot be any of those;
///   - `*241* (V) salle MA` sits under Mathématiques Appliquées, whose only
///     other room is `salle immersive N° 323 Bât 2`, and 1xx/2xx/3xx read as
///     floors of that same building.
/// Letters after the star are a capacity bucket (`*SALLES 30 PLACES`), not a
/// room, so the digits are required.
final RegExp _starred = RegExp(r'^\*\s*\d{2,3}');

/// Exam seating in the Halle Francis Querné, written as rows and wings.
final RegExp _halle = RegExp(
  r'^(rang\s*\d+\s*de|droite-|gauche-|aile\s+(est|ouest)|mur escalade)',
);

/// Session held online or off campus. Matched on the folded string.
const List<String> _remotePrefixes = <String>[
  '..a ',
  '..avisio',
  '... ',
  '.enseignement a l exterieur',
  'mooc',
  'zoom',
  'visio ',
  'cours en mooc',
];

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

/// Rooms ADE files under a department node without repeating the building.
/// Keyed on the full folded name, because several of these numbers also exist
/// in another building with a `bât` marker that must keep winning.
const Map<String, String> _departmentRooms = <String, String>{
  // Département GCU, building 7 on the plan.
  '001 - tp beton': '7',
  '001 a - tp beton': '7',
  '006 - tp routes +topo': '7',
  '006a - tp topo +  routes': '7',
  '010- tp meca des sols': '7',
  '018 - tp hydraulique doustens': '7',
  '101 - salle liibre service pour les etudiants': '7',
  '105 - tp structures': '7',
  '109 - tp meca des sols': '7',
  '118 - tp cartographie': '7',
  '134 salle de reunion gcu- vpi': '7',
  'amphi gc': '7',
  // Département GMA, building 11.
  'jeu de lean': '11',
  'jeu ddbrix 1': '11',
  'jeu ddbrix 2': '11',
  // Amphi André Bonnin under its ADE spelling.
  'amphi bonnin 78 places -modal-': '5',
};

/// ADE puts several rooms in one LOCATION when a session is split across them.
ResolvedRoom resolveRoom(String? raw, List<CampusPlace> places) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) return ResolvedRoom(raw: text);

  // The first part that places itself wins, so an "AUTRE SALLE" filler does
  // not hide the real room booked alongside it.
  var remote = false;
  for (final part in text.split(',')) {
    final one = _resolveOne(part.trim(), places);
    if (one == null) continue;
    if (one.isRemote) {
      remote = true;
      continue;
    }
    return ResolvedRoom(
      raw: text,
      place: one.place,
      buildingCode: one.buildingCode,
    );
  }
  return ResolvedRoom(raw: text, isRemote: remote);
}

/// Resolves a single room, or returns null when nothing matches.
ResolvedRoom? _resolveOne(String text, List<CampusPlace> places) {
  if (text.isEmpty) return null;

  // A room that names its own building needs no lookup, and is more reliable
  // than one: "Salle TP 2 A (115)-bat 6".
  final stated = _building.firstMatch(text);
  if (stated != null) {
    return ResolvedRoom(raw: text, buildingCode: stated.group(1));
  }

  // Before the parenthesis cut below, which would strip "(Allemand)" and
  // leave a bare star.
  if (_starred.hasMatch(text)) {
    return ResolvedRoom(raw: text, buildingCode: '2');
  }

  final full = foldForSearch(text);
  if (full.isEmpty) return null;

  for (final prefix in _remotePrefixes) {
    if (full.startsWith(prefix)) {
      return ResolvedRoom(raw: text, isRemote: true);
    }
  }

  if (_halle.hasMatch(full)) {
    return ResolvedRoom(raw: text, buildingCode: '17');
  }

  final department = _departmentRooms[full];
  if (department != null) {
    return ResolvedRoom(raw: text, buildingCode: department);
  }

  // Everything before the first parenthesis. ADE appends a site marker, and
  // sometimes trailing text after it, so cutting at "(" beats stripping a
  // trailing group.
  final name = foldForSearch(text.split('(').first);
  if (name.isEmpty) return null;

  final alias = _verifiedAliases[name] ?? _departmentRooms[name];
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
  return null;
}
