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

  test('a starred room number does not resolve', () {
    for (final raw in <String>[
      '*110* (V)co-modal',
      '*216* (V)',
      '*111 (VPI)',
      '*102* (VPI)',
      '*219* (V)co-modal',
    ]) {
      final r = resolveRoom(raw, _places);
      expect(r.isResolved, isFalse, reason: '$raw should not resolve');
      expect(r.mapQuery, isNull);
    }
  });

  test('null and empty rooms do not resolve', () {
    expect(resolveRoom(null, _places).isResolved, isFalse);
    expect(resolveRoom('', _places).isResolved, isFalse);
    expect(resolveRoom('   ', _places).isResolved, isFalse);
  });

  test('the raw string is always preserved for display', () {
    expect(resolveRoom('*216* (V)', _places).raw, '*216* (V)');
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
  });

  test('coverage over the real fixture rooms is 5 of 11', () {
    // Locks the number in the spec. If the places data grows, this test is
    // where the improvement gets recorded rather than silently drifting.
    const fixtureRooms = <String>[
      '',
      '*102* (VPI)',
      '*110* (V)co-modal',
      '*111 (VPI)',
      '*216* (V)',
      '*219* (V)co-modal',
      'Amphi A (V)',
      'Amphi B (V)',
      'Amphi C (V)',
      'Amphi M. DRISSI (V)',
      'Salle TP 2 A (115)-bat 6',
    ];
    final resolved = fixtureRooms
        .where((r) => resolveRoom(r, _places).isResolved)
        .length;
    expect(resolved, 5);
  });
}
