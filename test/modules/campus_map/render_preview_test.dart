@Tags(['preview'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/modules/campus_map/campus_geo.dart';
import 'package:notes_insa/modules/campus_map/map_painter.dart';

/// Renders the baked campus to a PNG for eyeballing. Not an assertion; run
/// with `--tags preview` and open the file it prints.
void main() {
  testWidgets('render the campus to a png', (tester) async {
    final geo = CampusGeoData.parse(
      File('assets/data/campus_geo.json').readAsStringSync(),
    );
    final geometry = CampusMapGeometry(geo);
    const size = Size(900, 1400);
    final camera = MapCamera.fit(geo.siteBounds.inflate(30), size);

    const palette = CampusMapPalette(
      ground: Color(0xFFF4F3F0),
      path: Color(0xFFD5D2CB),
      context: Color(0xFFE7E4DE),
      contextEdge: Color(0xFFDAD6CF),
      building: Color(0xFFCBC7BE),
      buildingEdge: Color(0xFF8C877C),
      selected: Color(0xFFF2C230),
      selectedEdge: Color(0xFF8A6D00),
    );
    const label = TextStyle(
      color: Color(0xFF4A463E),
      fontSize: 16,
      fontWeight: FontWeight.w600,
    );

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    CampusMapPainter(
      geometry: geometry,
      camera: camera,
      palette: palette,
      labels: LabelCache(),
      labelStyle: label,
      selectedLabelStyle: label.copyWith(color: const Color(0xFF241E00)),
      selected: '6',
    ).paint(canvas, size);

    final image = await recorder.endRecording().toImage(
      size.width.toInt(),
      size.height.toInt(),
    );
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final out = File('build/campus_preview.png');
    out.parent.createSync(recursive: true);
    out.writeAsBytesSync(png!.buffer.asUint8List());
    // ignore: avoid_print
    print('wrote ${out.absolute.path}');
  });
}
