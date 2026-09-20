import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/modules/associations/association.dart';
import 'package:notes_insa/core/time.dart';
import 'package:notes_insa/modules/associations/association_logo_assets.dart';
import 'package:notes_insa/modules/associations/association_local_logo_assets.dart';
import 'package:notes_insa/modules/associations/association_service.dart';

/// Guards the seed while it is filled in by hand. A row the app would silently
/// drop fails here instead, naming the row.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initCampusTime);
  final raw = File(Associations.assetPath).readAsStringSync();
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final rows = (decoded['associations'] as List).cast<Map<String, dynamic>>();

  // Parsed per test, not here: event dates need the timezone database, which
  // setUpAll loads after this function body has already run. Calling it too
  // early hits the parser's own tolerance and quietly yields an empty list.
  late List<Association> parsed;
  setUp(() => parsed = Associations.parse(raw));

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
      'jeux',
      'tech',
      'gastronomie',
      'engagement',
      'international',
      'entreprise',
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
    var checked = 0;
    for (final association in parsed) {
      final asset = association.logoAsset;
      if (asset == null) continue;
      checked++;
      expect(
        File(asset).existsSync(),
        isTrue,
        reason: '${association.id} points at a missing $asset',
      );
    }
    expect(
      checked,
      kBundledAssociationLogos.length + kBundledAssociationLocalLogos.length,
    );
  });

  test('every baked logo belongs to an association it was baked from', () {
    final byId = <String, Association>{for (final a in parsed) a.id: a};
    for (final entry in kBundledAssociationLogos.entries) {
      final association = byId[entry.key];
      expect(association, isNotNull, reason: '${entry.key} is not in the seed');
      expect(
        association!.logoUrl,
        entry.value,
        reason:
            '${entry.key} was baked from a URL the seed no longer carries; '
            're-run scripts/fetch_association_logos.py',
      );
    }
  });

  // The five the AEIR host does not serve. This list is what tells you when
  // one of them comes back.
  test('only the known-dead logo URLs have no bundled asset', () {
    const dead = <String>{
      'insaveur-biere',
      'insavoyarde',
      'secur-insa',
      'solidar-insa',
      'trombinoscope',
    };
    final without = <String>{
      for (final a in parsed)
        if (a.logoUrl != null && a.logoAsset == null) a.id,
    };
    expect(without, dead);
  });

  test('the baked assets are square, small, and all referenced', () async {
    final directory = Directory('assets/images/associations');
    final files = directory
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.webp'))
        .toList();

    final named = <String>{
      for (final f in files) f.uri.pathSegments.last.split('.').first,
    };
    expect(named, <String>{
      ...kBundledAssociationLogos.keys,
      ...kBundledAssociationLocalLogos.values.map(
        (filename) => filename.split('.').first,
      ),
    });

    var total = 0;
    for (final file in files) {
      final bytes = file.readAsBytesSync();
      total += bytes.length;
      expect(
        bytes.length,
        lessThan(32 * 1024),
        reason: '${file.path} is heavier than a logo needs to be',
      );

      // A slot that is not square draws a band across the circle, which is
      // the defect the baker exists to remove.
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      expect(
        <int>[descriptor.width, descriptor.height],
        <int>[192, 192],
        reason: '${file.path} is not a 192 square',
      );
      buffer.dispose();
    }
    expect(total, lessThan(768 * 1024));
  });

  test('the asset directory is declared to the bundler', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('- assets/images/associations/'));
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

  test('the seed actually has content', () {
    // The directory shows "Bientôt" while this is empty, so an accidental
    // truncation would ship as a plausible-looking empty state.
    expect(parsed.length, greaterThan(20));
  });

  test('every profile gives students enough context to choose it', () {
    for (final association in parsed) {
      expect(association.summary, isNotNull, reason: association.id);
      expect(association.description, isNotNull, reason: association.id);
    }
  });

  test('every link is a URL the app can open', () {
    for (final association in parsed) {
      for (final url in <String?>[
        association.links.website,
        association.links.discord,
        association.links.facebook,
        association.links.linkedin,
        ...association.events.map((e) => e.url),
      ]) {
        if (url == null) continue;
        final uri = Uri.tryParse(url);
        expect(uri?.hasScheme, isTrue, reason: '${association.id}: $url');
        expect(uri!.scheme, anyOf('http', 'https'), reason: association.id);
      }
    }
  });

  test('an event that names a venue also says which building', () {
    // The venue text alone gives no map action, which is the point of having
    // a code. A campus-wide event legitimately has neither.
    for (final association in parsed) {
      for (final event in association.events) {
        if (event.buildingCode == null) continue;
        expect(event.location, isNotNull, reason: event.id);
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
