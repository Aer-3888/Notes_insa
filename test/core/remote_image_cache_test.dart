import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/core/remote_image_cache.dart';

Future<Uint8List> _png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF336699),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

Future<(int, int)> _size(Uint8List bytes) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final descriptor = await ui.ImageDescriptor.encoded(buffer);
  final size = (descriptor.width, descriptor.height);
  buffer.dispose();
  return size;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('an oversized logo is stored at the size it is drawn', () {
    test('the longest side comes down and the shape is kept', () async {
      final raw = await _png(1400, 700);
      final small = await CachedRemoteImage.shrink(raw, 192);

      expect(await _size(small), (192, 96));
      expect(small.length, lessThan(raw.length));
    });

    test('a portrait logo is measured on its own longest side', () async {
      final small = await CachedRemoteImage.shrink(await _png(600, 1200), 192);

      expect(await _size(small), (96, 192));
    });

    test('an image already small enough is left alone', () async {
      final raw = await _png(120, 120);

      expect(await CachedRemoteImage.shrink(raw, 192), same(raw));
    });
  });

  test('the same URL at the same size is one cache entry', () {
    const a = CachedRemoteImage('https://example.org/a.png');
    const b = CachedRemoteImage('https://example.org/a.png');
    const other = CachedRemoteImage(
      'https://example.org/a.png',
      storedSize: 96,
    );

    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(other));
  });
}
