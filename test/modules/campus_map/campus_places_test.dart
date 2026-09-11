import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/modules/campus_map/campus_places.dart';

const String fixture = '''
[
  {"code": "19", "name": "Bibliothèque", "kind": "bu"},
  {"code": "3", "name": "Amphi B", "kind": "amphi"},
  {"code": "18", "name": "Département INFO et laboratoire IRISA", "kind": "batiment"},
  {"code": "", "name": "sans code", "kind": "service"},
  {"code": "9", "name": "mauvais genre", "kind": "piscine"},
  "pas un objet"
]
''';

void main() {
  test('parses valid rows and drops invalid ones', () {
    final places = CampusPlaces.parse(fixture);
    expect(places.map((p) => p.name), [
      'Bibliothèque',
      'Amphi B',
      'Département INFO et laboratoire IRISA',
    ]);
    expect(places.first.kind, PlaceKind.bu);
  });

  test('malformed JSON yields an empty list, never a throw', () {
    expect(CampusPlaces.parse('{not json'), isEmpty);
    expect(CampusPlaces.parse('{"a": 1}'), isEmpty);
  });

  test('search ignores case and accents and matches codes', () {
    final places = CampusPlaces.parse(fixture);
    final bu = places.first;
    expect(bu.matches('bibliotheque'), isTrue);
    expect(bu.matches('BIBLIO'), isTrue);
    expect(bu.matches('19'), isTrue);
    expect(bu.matches('amphi'), isFalse);
    expect(places[1].matches('amphi b'), isTrue);
    expect(places[2].matches('irisa'), isTrue);
    expect(bu.matches('   '), isTrue);
  });

  test('every kind has a French section label', () {
    for (final kind in PlaceKind.values) {
      expect(kind.label, isNotEmpty);
    }
    expect(PlaceKind.parse('residence'), PlaceKind.residence);
    expect(PlaceKind.parse('gymnase'), isNull);
  });

  test('the bundled places include searchable BU Beaulieu', () {
    final places = CampusPlaces.parse(
      File('assets/data/campus_places.json').readAsStringSync(),
    );
    final beaulieu = places.singleWhere((place) => place.code == 'BU-B');
    expect(beaulieu.name, 'BU Beaulieu');
    expect(beaulieu.kind, PlaceKind.bu);
    expect(beaulieu.matches('beaulieu'), isTrue);
  });

  test('the official plan URL is the INSA Rennes PDF', () {
    expect(kCampusPlanUrl, startsWith('https://www.insa-rennes.fr/'));
    expect(kCampusPlanUrl, endsWith('.pdf'));
  });
}
