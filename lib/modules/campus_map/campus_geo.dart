import 'dart:convert';
import 'dart:ui' show Offset, Rect;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Campus geometry baked from OpenStreetMap by `scripts/fetch_campus_geo.py`.
///
/// Coordinates are metres east and north of [CampusGeo.origin], so the whole
/// model is a flat plane; at a 400 m site the projection error stays below a
/// pixel.
@immutable
class CampusBuilding {
  CampusBuilding({
    required this.code,
    required this.name,
    required this.levels,
    required this.ring,
  }) : bounds = _boundsOf(ring),
       centroid = _centroidOf(ring);

  /// Building number on the INSA plan, or null for context geometry that
  /// carries no number.
  final String? code;
  final String? name;
  final int? levels;

  /// Closed ring, first point repeated last.
  final List<Offset> ring;
  final Rect bounds;
  final Offset centroid;

  bool get isNumbered => code != null;

  bool contains(Offset p) {
    if (!bounds.contains(p)) return false;
    var inside = false;
    for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final a = ring[i];
      final b = ring[j];
      if ((a.dy > p.dy) != (b.dy > p.dy) &&
          p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
        inside = !inside;
      }
    }
    return inside;
  }

  static Rect _boundsOf(List<Offset> ring) {
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final p in ring) {
      if (p.dx < minX) minX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy > maxY) maxY = p.dy;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// Area centroid, so a label sits inside an L-shaped building rather than
  /// in the notch a vertex average would pick.
  static Offset _centroidOf(List<Offset> ring) {
    var a = 0.0, cx = 0.0, cy = 0.0;
    for (var i = 0; i < ring.length - 1; i++) {
      final p = ring[i];
      final q = ring[i + 1];
      final cross = p.dx * q.dy - q.dx * p.dy;
      a += cross;
      cx += (p.dx + q.dx) * cross;
      cy += (p.dy + q.dy) * cross;
    }
    if (a.abs() < 1e-6) return _boundsOf(ring).center;
    return Offset(cx / (3 * a), cy / (3 * a));
  }
}

@immutable
class CampusEntrance {
  const CampusEntrance({
    required this.code,
    required this.kind,
    required this.node,
    required this.p,
  });

  final String code;

  /// `main` or `yes`. Service and emergency doors are dropped at bake time.
  final String kind;

  /// Index into [CampusGraph.nodes].
  final int node;
  final Offset p;
}

@immutable
class CampusGraph {
  const CampusGraph({required this.nodes, required this.edges});

  final List<Offset> nodes;

  /// `[from, to, cost]`, undirected. Cost is metres already weighted by
  /// surface, so steps and service roads lose to footpaths.
  final List<List<double>> edges;

  static const CampusGraph empty = CampusGraph(nodes: [], edges: []);
}

@immutable
class CampusGeo {
  const CampusGeo({
    required this.originLat,
    required this.originLon,
    required this.mPerDegLat,
    required this.mPerDegLon,
    required this.buildings,
    required this.entrances,
    required this.graph,
    required this.unmapped,
    required this.attribution,
  });

  final double originLat;
  final double originLon;
  final double mPerDegLat;
  final double mPerDegLon;

  final List<CampusBuilding> buildings;
  final List<CampusEntrance> entrances;
  final CampusGraph graph;

  /// Building codes with no footprint, mapped to why. The screen says so
  /// rather than dropping the place silently.
  final Map<String, String> unmapped;

  final String attribution;

  static const CampusGeo empty = CampusGeo(
    originLat: 0,
    originLon: 0,
    mPerDegLat: 1,
    mPerDegLon: 1,
    buildings: [],
    entrances: [],
    graph: CampusGraph.empty,
    unmapped: {},
    attribution: '',
  );

  bool get isEmpty => buildings.isEmpty;

  Offset toLocal(double lat, double lon) =>
      Offset((lon - originLon) * mPerDegLon, (lat - originLat) * mPerDegLat);

  CampusBuilding? byCode(String code) {
    for (final b in buildings) {
      if (b.code == code) return b;
    }
    return null;
  }

  CampusBuilding? hitTest(Offset p) {
    // Numbered buildings win: they are the only ones worth selecting, and
    // context geometry sometimes overlaps them.
    for (final b in buildings) {
      if (b.isNumbered && b.contains(p)) return b;
    }
    return null;
  }

  /// Bounds of the numbered site, used to frame the map on open.
  Rect get siteBounds {
    var r = Rect.zero;
    for (final b in buildings) {
      if (!b.isNumbered) continue;
      r = r == Rect.zero ? b.bounds : r.expandToInclude(b.bounds);
    }
    return r == Rect.zero ? const Rect.fromLTWH(-200, -200, 400, 400) : r;
  }
}

abstract final class CampusGeoData {
  static const String assetPath = 'assets/data/campus_geo.json';

  static CampusGeo parse(String json) {
    try {
      final root = jsonDecode(json);
      if (root is! Map) return CampusGeo.empty;
      final origin = root['origin'];
      if (origin is! Map) return CampusGeo.empty;

      final buildings = <CampusBuilding>[];
      for (final raw in (root['buildings'] as List? ?? const [])) {
        if (raw is! Map) continue;
        final ring = _ring(raw['ring']);
        if (ring.length < 4) continue;
        buildings.add(
          CampusBuilding(
            code: raw['code'] as String?,
            name: raw['name'] as String?,
            levels: (raw['levels'] as num?)?.toInt(),
            ring: ring,
          ),
        );
      }

      final entrances = <CampusEntrance>[];
      for (final raw in (root['entrances'] as List? ?? const [])) {
        if (raw is! Map) continue;
        final code = raw['code'];
        final p = _point(raw['p']);
        if (code is! String || p == null) continue;
        entrances.add(
          CampusEntrance(
            code: code,
            kind: raw['kind'] as String? ?? 'yes',
            node: (raw['node'] as num?)?.toInt() ?? -1,
            p: p,
          ),
        );
      }

      final g = root['graph'];
      final graph = g is Map
          ? CampusGraph(
              nodes: _ring(g['nodes']),
              edges: [
                for (final e in (g['edges'] as List? ?? const []))
                  if (e is List && e.length >= 3)
                    [
                      (e[0] as num).toDouble(),
                      (e[1] as num).toDouble(),
                      (e[2] as num).toDouble(),
                    ],
              ],
            )
          : CampusGraph.empty;

      return CampusGeo(
        originLat: (origin['lat'] as num).toDouble(),
        originLon: (origin['lon'] as num).toDouble(),
        mPerDegLat: (origin['mPerDegLat'] as num).toDouble(),
        mPerDegLon: (origin['mPerDegLon'] as num).toDouble(),
        buildings: buildings,
        entrances: entrances,
        graph: graph,
        unmapped: {
          for (final e in (root['unmapped'] as Map? ?? const {}).entries)
            e.key.toString(): e.value.toString(),
        },
        attribution: root['attribution'] as String? ?? '',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[CampusGeo] unreadable dataset: $e');
      return CampusGeo.empty;
    }
  }

  static List<Offset> _ring(Object? raw) {
    if (raw is! List) return const [];
    final out = <Offset>[];
    for (final p in raw) {
      final o = _point(p);
      if (o != null) out.add(o);
    }
    return out;
  }

  static Offset? _point(Object? raw) {
    if (raw is! List || raw.length < 2) return null;
    final x = raw[0], y = raw[1];
    if (x is! num || y is! num) return null;
    return Offset(x.toDouble(), y.toDouble());
  }

  static Future<CampusGeo> load() async {
    try {
      return parse(await rootBundle.loadString(assetPath));
    } catch (e) {
      if (kDebugMode) debugPrint('[CampusGeo] missing dataset: $e');
      return CampusGeo.empty;
    }
  }
}

final campusGeoProvider = FutureProvider<CampusGeo>(
  (ref) => CampusGeoData.load(),
);
