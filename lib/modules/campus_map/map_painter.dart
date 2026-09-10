import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'campus_geo.dart';

/// The camera over the campus plane. Metres east and north, so `y` grows
/// north and the projection flips it for the screen.
@immutable
class MapCamera {
  const MapCamera({
    required this.center,
    required this.metersPerPixel,
    this.bearingDegrees = 0,
  });

  final Offset center;
  final double metersPerPixel;
  final double bearingDegrees;

  static const double minMpp = 0.06;
  static const double maxMpp = 1.6;

  MapCamera copyWith({
    Offset? center,
    double? metersPerPixel,
    double? bearingDegrees,
  }) => MapCamera(
    center: center ?? this.center,
    metersPerPixel: (metersPerPixel ?? this.metersPerPixel).clamp(
      minMpp,
      maxMpp,
    ),
    bearingDegrees: bearingDegrees ?? this.bearingDegrees,
  );

  /// World metres to screen pixels. [bearingDegrees] is the world direction
  /// displayed at the top of the device: zero keeps north at the top.
  Matrix4 matrix(Size size) {
    final s = 1.0 / metersPerPixel;
    final bearing = bearingDegrees * math.pi / 180;
    return Matrix4.identity()
      ..translateByDouble(size.width / 2, size.height / 2, 0, 1)
      ..rotateZ(-bearing)
      ..scaleByDouble(s, -s, 1, 1)
      ..translateByDouble(-center.dx, -center.dy, 0, 1);
  }

  Offset toScreen(Offset world, Size size) {
    final bearing = bearingDegrees * math.pi / 180;
    final east = (world.dx - center.dx) / metersPerPixel;
    final screenNorth = -(world.dy - center.dy) / metersPerPixel;
    final cosine = math.cos(bearing);
    final sine = math.sin(bearing);
    return Offset(
      size.width / 2 + cosine * east + sine * screenNorth,
      size.height / 2 - sine * east + cosine * screenNorth,
    );
  }

  Offset toWorld(Offset screen, Size size) {
    final bearing = bearingDegrees * math.pi / 180;
    final x = screen.dx - size.width / 2;
    final y = screen.dy - size.height / 2;
    final cosine = math.cos(bearing);
    final sine = math.sin(bearing);
    final east = cosine * x - sine * y;
    final screenNorth = sine * x + cosine * y;
    return Offset(
      center.dx + east * metersPerPixel,
      center.dy - screenNorth * metersPerPixel,
    );
  }

  /// Frames [bounds] with a margin, so the site opens fully visible.
  static MapCamera fit(Rect bounds, Size size, {double padding = 48}) {
    final w = size.width - padding * 2;
    final h = size.height - padding * 2;
    if (w <= 0 || h <= 0 || bounds.isEmpty) {
      return MapCamera(center: bounds.center, metersPerPixel: 0.4);
    }
    final mpp = (bounds.width / w).clamp(minMpp, maxMpp);
    final mppY = (bounds.height / h).clamp(minMpp, maxMpp);
    return MapCamera(
      center: bounds.center,
      metersPerPixel: mpp > mppY ? mpp : mppY,
    );
  }
}

/// Colours resolved once per build, so the painter never touches a
/// BuildContext.
@immutable
class CampusMapPalette {
  const CampusMapPalette({
    required this.ground,
    required this.path,
    required this.context,
    required this.contextEdge,
    required this.building,
    required this.buildingEdge,
    required this.selected,
    required this.selectedEdge,
  });

  final Color ground;
  final Color path;
  final Color context;
  final Color contextEdge;
  final Color building;
  final Color buildingEdge;
  final Color selected;
  final Color selectedEdge;

  /// Disc under the marker, sized to the fix the phone claims.
  Color get locationHalo => selected.withValues(alpha: 0.14);
}

/// World-space geometry built once per dataset. Only the projection runs
/// per frame.
class CampusMapGeometry {
  CampusMapGeometry(this.geo) {
    for (final e in geo.graph.edges) {
      final a = e[0].toInt(), b = e[1].toInt();
      if (a < 0 || b < 0) continue;
      if (a >= geo.graph.nodes.length || b >= geo.graph.nodes.length) continue;
      final pa = geo.graph.nodes[a];
      final pb = geo.graph.nodes[b];
      footways.moveTo(pa.dx, pa.dy);
      footways.lineTo(pb.dx, pb.dy);
    }
    for (final b in geo.buildings) {
      final p = Path()..addPolygon(b.ring, true);
      if (b.isNumbered) {
        numbered.add((b, p));
      } else {
        context.addPath(p, Offset.zero);
      }
    }
  }

  final CampusGeo geo;
  final Path footways = Path();
  final Path context = Path();
  final List<(CampusBuilding, Path)> numbered = [];
}

/// Laid-out building numbers, kept between frames. Laying these out every
/// frame is the obvious way to make the map stutter.
class LabelCache {
  final Map<String, TextPainter> _painters = {};

  TextPainter get(String text, TextStyle style) {
    // Keyed by style too: selected and unselected labels alternate within
    // one frame, and invalidating on style change would clear every frame.
    return _painters.putIfAbsent('$text|${style.hashCode}', () {
      final tp = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      return tp;
    });
  }
}

class CampusMapPainter extends CustomPainter {
  CampusMapPainter({
    required this.geometry,
    required this.camera,
    required this.palette,
    required this.labels,
    required this.labelStyle,
    required this.selectedLabelStyle,
    required this.selected,
    this.route = const <Offset>[],
    this.currentLocation,
    this.currentAccuracyMeters,
    this.currentHeadingDegrees,
  });

  final CampusMapGeometry geometry;
  final MapCamera camera;
  final CampusMapPalette palette;
  final LabelCache labels;
  final TextStyle labelStyle;
  final TextStyle selectedLabelStyle;
  final String? selected;
  final List<Offset> route;
  final Offset? currentLocation;
  final double? currentHeadingDegrees;
  final double? currentAccuracyMeters;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = palette.ground);

    final scale = 1.0 / camera.metersPerPixel;
    canvas.save();
    canvas.transform(camera.matrix(size).storage);

    canvas.drawPath(
      geometry.footways,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4 / scale
        ..strokeCap = StrokeCap.round
        ..color = palette.path,
    );

    canvas.drawPath(geometry.context, Paint()..color = palette.context);
    canvas.drawPath(
      geometry.context,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1 / scale
        ..color = palette.contextEdge,
    );

    for (final (building, path) in geometry.numbered) {
      final isSelected = building.code == selected;
      canvas.drawPath(
        path,
        Paint()..color = isSelected ? palette.selected : palette.building,
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (isSelected ? 2.0 : 1.0) / scale
          ..color = isSelected ? palette.selectedEdge : palette.buildingEdge,
      );
    }

    if (route.length > 1) {
      final path = Path()..moveTo(route.first.dx, route.first.dy);
      for (final point in route.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4 / scale
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = palette.selected,
      );
    }
    canvas.restore();
    _paintCurrentLocation(canvas, size);
    _paintLabels(canvas, size);
  }

  void _paintCurrentLocation(Canvas canvas, Size size) {
    final location = currentLocation;
    if (location == null) return;
    final at = camera.toScreen(location, size);
    final accuracy = currentAccuracyMeters;
    if (accuracy != null && accuracy > 0) {
      // Only once the claimed error is wider than the marker itself, so a
      // good fix stays a dot rather than a smudge.
      final radius = accuracy / camera.metersPerPixel;
      if (radius > 12) {
        canvas.drawCircle(at, radius, Paint()..color = palette.locationHalo);
      }
    }
    canvas.drawCircle(at, 9, Paint()..color = palette.ground);
    canvas.drawCircle(at, 6, Paint()..color = palette.selected);
    canvas.drawCircle(
      at,
      6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = palette.selectedEdge,
    );
    final heading = currentHeadingDegrees;
    if (heading == null || !heading.isFinite) return;
    final relativeHeading = (heading - camera.bearingDegrees) * math.pi / 180;
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(relativeHeading);
    final arrow = Path()
      ..moveTo(0, -15)
      ..lineTo(6, 1)
      ..lineTo(0, -2)
      ..lineTo(-6, 1)
      ..close();
    canvas.drawPath(arrow, Paint()..color = palette.selected);
    canvas.restore();
  }

  void _paintLabels(Canvas canvas, Size size) {
    final placed = <Rect>[];
    final viewport = Offset.zero & size;

    // Selection first, so a crowded corner never drops the label the user
    // just asked for.
    final ordered = [...geometry.numbered]
      ..sort((a, b) {
        final sa = a.$1.code == selected ? 0 : 1;
        final sb = b.$1.code == selected ? 0 : 1;
        if (sa != sb) return sa - sb;
        return b.$1.bounds.width.compareTo(a.$1.bounds.width);
      });

    for (final (building, _) in ordered) {
      final code = building.code;
      if (code == null) continue;
      final isSelected = code == selected;
      final tp = labels.get(code, isSelected ? selectedLabelStyle : labelStyle);
      final at = camera.toScreen(building.centroid, size);
      final rect = Rect.fromCenter(
        center: at,
        width: tp.width + 8,
        height: tp.height + 6,
      );
      if (!viewport.overlaps(rect)) continue;
      if (placed.any((r) => r.overlaps(rect))) continue;
      placed.add(rect);
      tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(CampusMapPainter old) =>
      old.camera.center != camera.center ||
      old.camera.metersPerPixel != camera.metersPerPixel ||
      old.camera.bearingDegrees != camera.bearingDegrees ||
      old.selected != selected ||
      old.route != route ||
      old.currentLocation != currentLocation ||
      old.currentAccuracyMeters != currentAccuracyMeters ||
      old.currentHeadingDegrees != currentHeadingDegrees ||
      old.palette != palette ||
      old.labelStyle != labelStyle ||
      !identical(old.geometry, geometry);
}
