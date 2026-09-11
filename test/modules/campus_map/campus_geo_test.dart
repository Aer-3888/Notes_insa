import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/modules/campus_map/campus_geo.dart';
import 'package:notes_insa/modules/campus_map/campus_route.dart';

/// Guards on the baked asset. `scripts/fetch_campus_geo.py` validates at bake
/// time; these check the same promises survive parsing, so a bad re-bake fails
/// here rather than on a phone.
void main() {
  final geo = CampusGeoData.parse(
    File('assets/data/campus_geo.json').readAsStringSync(),
  );
  final codes =
      (jsonDecode(File('assets/data/campus_places.json').readAsStringSync())
              as List)
          .map((p) => (p as Map)['code'] as String)
          .toSet();

  test('the asset parses into geometry', () {
    expect(geo.isEmpty, isFalse);
    expect(geo.buildings.length, greaterThan(20));
    expect(geo.graph.nodes, isNotEmpty);
    expect(geo.graph.edges, isNotEmpty);
  });

  test('includes both selected restaurants with routable entrances', () {
    expect(geo.byCode('RU-E')?.name, 'Resto U’ Étoile');
    expect(geo.byCode('RU-A')?.name, 'Resto U’ Astrolabe');
    expect(
      geo.entrances.any(
        (entrance) => entrance.code == 'RU-E' && entrance.node == 235,
      ),
      isTrue,
    );
    expect(
      geo.entrances.any(
        (entrance) => entrance.code == 'RU-A' && entrance.node == 1388,
      ),
      isTrue,
    );
    final start = geo.byCode('12')!.centroid;
    expect(routeToBuilding(geo, start, 'RU-E'), isNotNull);
    expect(routeToBuilding(geo, start, 'RU-A'), isNotNull);
  });

  test('includes BU Beaulieu with a routable entrance', () {
    expect(geo.byCode('BU-B')?.name, 'BU Beaulieu');
    expect(
      geo.entrances.any(
        (entrance) => entrance.code == 'BU-B' && entrance.node == 1428,
      ),
      isTrue,
    );
    final start = geo.byCode('12')!.centroid;
    expect(routeToBuilding(geo, start, 'BU-B'), isNotNull);
  });

  test('every place code has a footprint unless declared unmapped', () {
    final missing = codes
        .where((c) => geo.byCode(c) == null && !geo.unmapped.containsKey(c))
        .toList();
    expect(missing, isEmpty, reason: 'codes with no footprint: $missing');
  });

  test('every mapped code has a usable entrance on the graph', () {
    for (final code in codes) {
      if (geo.byCode(code) == null) continue;
      final here = geo.entrances.where((e) => e.code == code);
      expect(here, isNotEmpty, reason: 'bâtiment $code has no entrance');
      expect(
        here.every((e) => e.node >= 0 && e.node < geo.graph.nodes.length),
        isTrue,
        reason: 'bâtiment $code has an entrance off the graph',
      );
    }
  });

  test('graph edges reference nodes that exist', () {
    for (final e in geo.graph.edges) {
      expect(e[0].toInt(), inInclusiveRange(0, geo.graph.nodes.length - 1));
      expect(e[1].toInt(), inInclusiveRange(0, geo.graph.nodes.length - 1));
      expect(e[2], greaterThan(0));
    }
  });

  test('the site is campus-sized, not a continent', () {
    final b = geo.siteBounds;
    expect(b.width, inInclusiveRange(200, 1200));
    expect(b.height, inInclusiveRange(200, 1200));
  });

  test('tapping a building centroid selects that building', () {
    final numbered = geo.buildings.where((b) => b.isNumbered).toList();
    final hits = numbered
        .where((b) => geo.hitTest(b.centroid)?.code == b.code)
        .length;
    // Some footprints are L-shaped or nest inside another, so this is a
    // ratio rather than an equality.
    expect(hits / numbered.length, greaterThan(0.8));
  });

  test('tapping far outside the site selects nothing', () {
    expect(geo.hitTest(const Offset(50000, 50000)), isNull);
  });

  test('the OpenStreetMap credit survives the bake', () {
    expect(geo.attribution, contains('OpenStreetMap'));
  });

  test('a broken asset degrades to empty rather than throwing', () {
    expect(CampusGeoData.parse('not json').isEmpty, isTrue);
    expect(CampusGeoData.parse('{}').isEmpty, isTrue);
    expect(CampusGeoData.parse('[]').isEmpty, isTrue);
  });
}
