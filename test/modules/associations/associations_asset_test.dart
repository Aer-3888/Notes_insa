import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/core/time.dart';
import 'package:notes_insa/modules/associations/association_service.dart';

/// Guards the seed while it is filled in by hand. A row the app would silently
/// drop fails here instead, naming the row.
void main() {
  setUpAll(initCampusTime);
  final raw = File(Associations.assetPath).readAsStringSync();
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final rows = (decoded['associations'] as List).cast<Map<String, dynamic>>();
  final parsed = Associations.parse(raw);

  test('the seed is at the version the app reads', () {
    expect(decoded['version'], Associations.supportedVersion);
  });

  test('every row in the file survives parsing', () {
    // Catches a missing id, an empty name, or an unparseable date, any of
    // which would make an association vanish from the app with no error.
    expect(
      parsed.length,
      rows.length,
      reason: 'a row was dropped, check id, name and event startsAt',
    );
  });

  test('ids are unique and slug-shaped', () {
    final seen = <String>{};
    for (final association in parsed) {
      expect(
        seen.add(association.id),
        isTrue,
        reason: 'duplicate id ${association.id}',
      );
      expect(
        association.id,
        matches(RegExp(r'^[a-z0-9][a-z0-9-]*$')),
        reason: '${association.id} must be a lowercase slug',
      );
    }
  });

  test('event ids are unique across the whole file', () {
    // Follows and notifications address an event by id alone.
    final seen = <String>{};
    for (final association in parsed) {
      for (final event in association.events) {
        expect(seen.add(event.id), isTrue, reason: 'duplicate id ${event.id}');
      }
    }
  });

  test('categories are ones the app knows', () {
    // parse() silently falls back to autre, so a typo would otherwise ship.
    const known = <String>{
      'bde',
      'sport',
      'culture',
      'tech',
      'solidarite',
      'media',
      'filiere',
      'autre',
    };
    for (final row in rows) {
      final category = row['category'];
      if (category == null) continue;
      expect(known, contains(category), reason: 'in ${row['id']}');
    }
  });

  test('a declared logo actually exists', () {
    for (final association in parsed) {
      final asset = association.logoAsset;
      if (asset == null) continue;
      expect(
        File(asset).existsSync(),
        isTrue,
        reason: '${association.id} points at a missing $asset',
      );
    }
  });

  test('building codes are on the campus plan', () async {
    final places = jsonDecode(
      File('assets/data/campus_places.json').readAsStringSync(),
    );
    final codes = <String>{
      for (final place in places as List) place['code'] as String,
    };
    for (final association in parsed) {
      for (final code in <String?>[
        association.buildingCode,
        ...association.events.map((e) => e.buildingCode),
      ]) {
        if (code == null) continue;
        expect(codes, contains(code), reason: '${association.id} uses $code');
      }
    }
  });

  test('an Instagram handle is stored without the arobase', () {
    for (final association in parsed) {
      final handle = association.links.instagram;
      if (handle == null) continue;
      expect(handle.startsWith('@'), isFalse, reason: association.id);
    }
  });
}
