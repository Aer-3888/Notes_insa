import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/modules/campus_map/campus_places.dart';
import 'package:notes_insa/modules/schedule/room_lookup.dart';

const _places = <CampusPlace>[
  CampusPlace(code: '3', name: 'Amphi A', kind: PlaceKind.amphi),
  CampusPlace(code: '3', name: 'Amphi B', kind: PlaceKind.amphi),
  CampusPlace(code: '3', name: 'Amphi C', kind: PlaceKind.amphi),
  CampusPlace(code: '5', name: 'Amphi André Bonnin', kind: PlaceKind.amphi),
  // Amphi D, renamed in 2022. Building 4, verified against the campus plan.
  CampusPlace(code: '4', name: 'Amphi M. DRISSI', kind: PlaceKind.amphi),
  CampusPlace(code: '7', name: 'Amphi GCU', kind: PlaceKind.amphi),
  CampusPlace(
    code: '17',
    name: 'Halle polyvalente Francis Querné',
    kind: PlaceKind.service,
  ),
];

void main() {
  test('an amphi resolves to its building', () {
    final r = resolveRoom('Amphi C (V)', _places);
    expect(r.isResolved, isTrue);
    expect(r.buildingCode, '3');
    expect(r.place?.name, 'Amphi C');
    expect(r.mapQuery, 'Amphi C');
  });

  test('a bat fragment wins without any lookup', () {
    final r = resolveRoom('Salle TP 2 A (115)-bat 6', _places);
    expect(r.isResolved, isTrue);
    expect(r.buildingCode, '6');
    expect(r.place, isNull);
    expect(r.mapQuery, '6');
  });

  test('Amphi A does not match Amphi André Bonnin', () {
    // CampusPlace.matches() is a contains search and would match both. This
    // lookup must be exact, or the map action sends people to building 5.
    expect(resolveRoom('Amphi A (V)', _places).buildingCode, '3');
  });

  test('a starred room number resolves to building 2', () {
    for (final raw in <String>[
      '*110* (V)co-modal',
      '*216* (V)',
      '*111 (VPI)',
      '*102* (VPI)',
      '*219* (V)co-modal',
      '*131*(V) 35 places',
      '*106  (V)co-modal',
      '*241*  (V) salle MA',
    ]) {
      final r = resolveRoom(raw, _places);
      expect(r.isResolved, isTrue, reason: '$raw should resolve');
      expect(r.buildingCode, '2', reason: raw);
      expect(r.mapQuery, '2');
    }
  });

  test('a starred language room still resolves to building 2', () {
    // The parenthesised language name must not be mistaken for a site marker.
    expect(resolveRoom('*228 (Allemand)*  (V)', _places).buildingCode, '2');
    expect(resolveRoom('*224 (Espagnol)*  (V)', _places).buildingCode, '2');
    expect(resolveRoom('*218 (V) LABO LANGUE', _places).buildingCode, '2');
  });

  test('a starred capacity bucket is not a room', () {
    // ADE parent nodes, never a place a student walks to.
    for (final raw in <String>['*SALLES 30 PLACES', '*SALLES 42 PLACES']) {
      expect(resolveRoom(raw, _places).isResolved, isFalse, reason: raw);
    }
  });

  test('null and empty rooms do not resolve', () {
    expect(resolveRoom(null, _places).isResolved, isFalse);
    expect(resolveRoom('', _places).isResolved, isFalse);
    expect(resolveRoom('   ', _places).isResolved, isFalse);
  });

  test('the raw string is always preserved for display', () {
    expect(resolveRoom('*216* (V)', _places).raw, '*216* (V)');
    expect(resolveRoom('AUTRE  SALLE', _places).raw, 'AUTRE  SALLE');
  });

  test('matching ignores case and accents', () {
    expect(resolveRoom('AMPHI ANDRE BONNIN (V)', _places).buildingCode, '5');
  });

  test('verified department aliases resolve without a fuzzy match', () {
    expect(resolveRoom('Département INFO', _places).buildingCode, '18');
    expect(resolveRoom('HUMANITES', _places).buildingCode, '6');
  });

  test('the official INFO room prefix resolves to building 18', () {
    expect(resolveRoom('INF-016 (TD INFO) (VPI)', _places).buildingCode, '18');
    expect(resolveRoom('INF-PC2  (VPI):134', _places).buildingCode, '18');
    expect(resolveRoom('INF-EAUX (V):118', _places).buildingCode, '18');
  });

  test('ADE lists several rooms in one LOCATION, the first one wins', () {
    final r = resolveRoom('*230*  (V),*231*  (V)', _places);
    expect(r.buildingCode, '2');
    // Display keeps the whole booking, not just the room we resolved.
    expect(r.raw, '*230*  (V),*231*  (V)');
  });

  test('an unresolvable first room does not hide a resolvable second', () {
    final r = resolveRoom('AUTRE  SALLE,E&T4 (114)-bât 5-1er etage', _places);
    expect(r.buildingCode, '5');
  });

  test('the Halle Francis Querné exam seating resolves to building 17', () {
    for (final raw in <String>[
      'RANG 01 de 1 à 30',
      'RANG 18 de  499 à 526',
      'DROITE- est',
      'GAUCHE- ouest',
      'AILE EST.',
      'AILE OUEST',
      'MUR ESCALADE',
    ]) {
      expect(resolveRoom(raw, _places).buildingCode, '17', reason: raw);
    }
  });

  test('GCU teaching rooms resolve to building 7', () {
    for (final raw in <String>[
      '001 - TP Béton',
      '105 - TP Structures',
      '118 - TP Cartographie',
      '134 SALLE DE REUNION GCU- VPI',
      'AMPHI GC   (V)',
    ]) {
      expect(resolveRoom(raw, _places).buildingCode, '7', reason: raw);
    }
  });

  test('a GCU room number does not capture the GMA room of the same number', () {
    // "018 - TP Hydraulique" is GCU, "018 -bat 11-" is GMA. The bât marker wins.
    expect(
      resolveRoom('018 - TP Hydraulique DOUSTENS', _places).buildingCode,
      '7',
    );
    expect(resolveRoom('018 -bat 11-', _places).buildingCode, '11');
  });

  test('remote sessions are flagged and offer no map', () {
    for (final raw in <String>[
      '..a Séance à distance asynchrone-',
      '..a Séance à distance synchrone- zoom',
      '..a Classe virtuelle-',
      '..a distance',
      '... MOODLE',
      'ZOOM',
      'MOOC RISQUE',
      '.ENSEIGNEMENT A L EXTERIEUR DE L INSA',
    ]) {
      final r = resolveRoom(raw, _places);
      expect(r.isRemote, isTrue, reason: '$raw should read as remote');
      expect(r.isResolved, isFalse, reason: '$raw has no building');
      expect(r.mapQuery, isNull);
    }
  });

  test('an on-campus room is never flagged remote', () {
    expect(resolveRoom('*216* (V)', _places).isRemote, isFalse);
    expect(resolveRoom('Amphi C (V)', _places).isRemote, isFalse);
  });

  test('rooms we genuinely cannot place stay unresolved', () {
    // Better a missing map action than one that sends people to the wrong door.
    for (final raw in <String>[
      'AUTRE  SALLE',
      'ENCR 225',
      'ENSCR 123',
      'ELE  SALLE INFO -105-',
      'Salle 1657',
    ]) {
      final r = resolveRoom(raw, _places);
      expect(r.isResolved, isFalse, reason: raw);
      expect(r.isRemote, isFalse, reason: raw);
    }
  });
}
