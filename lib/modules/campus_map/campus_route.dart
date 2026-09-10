import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'package:flutter/foundation.dart';

import 'campus_geo.dart';

@immutable
class CampusRoute {
  const CampusRoute({
    required this.buildingCode,
    required this.entrance,
    required this.points,
    required this.distanceMeters,
  });

  final String buildingCode;
  final CampusEntrance entrance;
  final List<Offset> points;
  final double distanceMeters;

  Rect get bounds {
    if (points.isEmpty) return Rect.zero;
    var left = points.first.dx;
    var right = left;
    var top = points.first.dy;
    var bottom = top;
    for (final point in points.skip(1)) {
      left = math.min(left, point.dx);
      right = math.max(right, point.dx);
      top = math.min(top, point.dy);
      bottom = math.max(bottom, point.dy);
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }
}

/// A conservative campus walking estimate based on about 1.3 metres/second.
int estimatedWalkingMinutes(
  double distanceMeters, {
  double walkingSpeedMetersPerSecond = 1.3,
}) {
  if (!distanceMeters.isFinite || distanceMeters <= 0) return 0;
  if (!walkingSpeedMetersPerSecond.isFinite ||
      walkingSpeedMetersPerSecond <= 0) {
    return 0;
  }
  final seconds = distanceMeters / walkingSpeedMetersPerSecond;
  return math.max(1, (seconds / 60).ceil());
}

String approximateWalkingTimeLabel(double distanceMeters) {
  final minutes = estimatedWalkingMinutes(distanceMeters);
  if (minutes == 0) return 'moins d’une minute';
  return '≈ $minutes min';
}

/// Finds a walking route from a GPS position to a building entrance.
///
/// The GPS point is snapped to the nearest node of the bundled campus graph.
/// Dijkstra then chooses the cheapest reachable entrance, so a `main` entrance
/// is preferred only when it does not make the route substantially longer.
CampusRoute? routeToBuilding(
  CampusGeo geo,
  Offset origin,
  String buildingCode,
) {
  final nodes = geo.graph.nodes;
  if (nodes.isEmpty) return null;

  final entrances = geo.entrances
      .where(
        (entrance) =>
            entrance.code == buildingCode &&
            entrance.node >= 0 &&
            entrance.node < nodes.length,
      )
      .toList();
  if (entrances.isEmpty) return null;

  var start = 0;
  var nearestSquared = double.infinity;
  for (var i = 0; i < nodes.length; i++) {
    final delta = nodes[i] - origin;
    final squared = delta.dx * delta.dx + delta.dy * delta.dy;
    if (squared < nearestSquared) {
      nearestSquared = squared;
      start = i;
    }
  }
  // The graph covers the campus approaches (including the metro), but it is
  // not a city router. A long straight snap would look like a safe footpath
  // when the user is actually outside the covered area.
  if (nearestSquared > 150 * 150) return null;

  final adjacency = List<List<(int, double)>>.generate(
    nodes.length,
    (_) => <(int, double)>[],
  );
  for (final edge in geo.graph.edges) {
    if (edge.length < 3) continue;
    final from = edge[0].toInt();
    final to = edge[1].toInt();
    if (from < 0 || to < 0 || from >= nodes.length || to >= nodes.length) {
      continue;
    }
    final cost = edge[2];
    if (!cost.isFinite || cost < 0) continue;
    adjacency[from].add((to, cost));
    adjacency[to].add((from, cost));
  }

  final distances = List<double>.filled(nodes.length, double.infinity);
  final previous = List<int>.filled(nodes.length, -1);
  final visited = List<bool>.filled(nodes.length, false);
  distances[start] = math.sqrt(nearestSquared);

  for (var step = 0; step < nodes.length; step++) {
    var current = -1;
    var best = double.infinity;
    for (var i = 0; i < nodes.length; i++) {
      if (!visited[i] && distances[i] < best) {
        current = i;
        best = distances[i];
      }
    }
    if (current < 0) break;
    visited[current] = true;
    for (final (next, cost) in adjacency[current]) {
      final candidate = best + cost;
      if (candidate < distances[next]) {
        distances[next] = candidate;
        previous[next] = current;
      }
    }
  }

  CampusEntrance? destination;
  var destinationCost = double.infinity;
  for (final entrance in entrances) {
    // A small preference breaks near-ties in favour of an entrance explicitly
    // tagged as the main door without choosing it from the opposite side.
    final preference = entrance.kind == 'main' ? 0.0 : 3.0;
    final cost = distances[entrance.node] + preference;
    if (cost < destinationCost) {
      destination = entrance;
      destinationCost = cost;
    }
  }
  if (destination == null || !destinationCost.isFinite) return null;

  final nodePath = <int>[];
  var cursor = destination.node;
  while (cursor >= 0) {
    nodePath.add(cursor);
    if (cursor == start) break;
    cursor = previous[cursor];
  }
  if (nodePath.last != start) return null;
  final points = <Offset>[origin];
  for (final node in nodePath.reversed) {
    if ((nodes[node] - points.last).distance > 0.1) points.add(nodes[node]);
  }
  if ((destination.p - points.last).distance > 0.1) {
    points.add(destination.p);
  }

  var distance = 0.0;
  for (var i = 1; i < points.length; i++) {
    distance += (points[i] - points[i - 1]).distance;
  }
  return CampusRoute(
    buildingCode: buildingCode,
    entrance: destination,
    points: List<Offset>.unmodifiable(points),
    distanceMeters: distance,
  );
}
