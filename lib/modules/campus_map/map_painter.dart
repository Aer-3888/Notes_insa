import 'package:flutter/material.dart';

import 'campus_geo.dart';

/// The camera over the campus plane. Metres east and north, so `y` grows
/// north and the projection flips it for the screen.
@immutable
class MapCamera {
  const MapCamera({required this.center, required this.metersPerPixel});

  final Offset center;
  final double metersPerPixel;

  static const double minMpp = 0.06;
  static const double maxMpp = 1.6;

  MapCamera copyWith({Offset? center, double? metersPerPixel}) => MapCamera(
    center: center ?? this.center,
    metersPerPixel: (metersPerPixel ?? this.metersPerPixel).clamp(
      minMpp,
      maxMpp,
    ),
  );

  /// World metres to screen pixels. A similarity transform for now; the
  /// rotation and pitch terms arrive with the 3D camera.
  Matrix4 matrix(Size size) {
    final s = 1.0 / metersPerPixel;
    return Matrix4.identity()
      ..translateByDouble(size.width / 2, size.height / 2, 0, 1)
      ..scaleByDouble(s, -s, 1, 1)
      ..translateByDouble(-center.dx, -center.dy, 0, 1);
  }

  Offset toScreen(Offset world, Size size) => Offset(
    size.width / 2 + (world.dx - center.dx) / metersPerPixel,
    size.height / 2 - (world.dy - center.dy) / metersPerPixel,
  );

  Offset toWorld(Offset screen, Size size) => Offset(
    center.dx + (screen.dx - size.width / 2) * metersPerPixel,
    center.dy - (screen.dy - size.height / 2) * metersPerPixel,
  );

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
  });

  final CampusMapGeometry geometry;
  final MapCamera camera;
  final CampusMapPalette palette;
  final LabelCache labels;
  final TextStyle labelStyle;
  final TextStyle selectedLabelStyle;
  final String? selected;

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
    canvas.restore();
    _paintLabels(canvas, size);
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
      old.selected != selected ||
      old.palette != palette ||
      old.labelStyle != labelStyle ||
      !identical(old.geometry, geometry);
}
