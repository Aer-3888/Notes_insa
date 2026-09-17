import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// A third-party image, kept on disk at the size this app actually draws.
///
/// The association logos are the case this exists for: fifty-one files, 7.7 MB,
/// several of them 3000 px square, every one of them destined for a 40 dp
/// avatar. Flutter's image cache holds nothing across a restart, and
/// `cacheWidth` only shrinks what is kept, not what the decoder has to build
/// first, so scrolling the directory paid for the full-size bitmaps again on
/// every launch. Here each URL is fetched once, re-encoded down to
/// [storedSize], and read from a small local file ever after.
@immutable
class CachedRemoteImage extends ImageProvider<CachedRemoteImage> {
  const CachedRemoteImage(this.url, {this.storedSize = 192});

  final String url;

  /// Longest side of the copy kept on disk, in pixels. Large enough for the
  /// biggest slot the image appears in, on the densest screen.
  final int storedSize;

  static const Duration _timeout = Duration(seconds: 20);
  static const Duration _maxAge = Duration(days: 30);

  /// Fifty rows entering the viewport at once would otherwise open fifty
  /// connections and decode fifty full-size images together.
  static final _Gate _gate = _Gate(4);

  /// A URL the source does not serve. Without this every rebuild asks again.
  static final Set<String> _missing = <String>{};

  static Directory? _directory;

  @visibleForTesting
  static void resetForTest() {
    _missing.clear();
    _directory = null;
  }

  @override
  Future<CachedRemoteImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<CachedRemoteImage>(this);

  @override
  ImageStreamCompleter loadImage(
    CachedRemoteImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _loadAsync(key, decode),
    scale: 1,
    debugLabel: key.url,
    informationCollector: () => <DiagnosticsNode>[
      ErrorDescription('Image URL: ${key.url}'),
    ],
  );

  Future<ui.Codec> _loadAsync(
    CachedRemoteImage key,
    ImageDecoderCallback decode,
  ) async {
    final bytes = await _bytes(key);
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  Future<Uint8List> _bytes(CachedRemoteImage key) async {
    if (_missing.contains(key.url)) {
      PaintingBinding.instance.imageCache.evict(key);
      throw StateError('No image at ${key.url}');
    }
    final file = await _fileFor(key);
    if (await _isFresh(file)) return file.readAsBytes();
    return _gate.run(() async {
      if (await _isFresh(file)) return file.readAsBytes();
      try {
        final downloaded = await _download(key);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(downloaded, flush: true);
        return downloaded;
      } catch (e) {
        // An expired copy still draws correctly, and the source being briefly
        // unreachable is not a reason to fall back to initials.
        if (file.existsSync()) return file.readAsBytes();
        _missing.add(key.url);
        PaintingBinding.instance.imageCache.evict(key);
        rethrow;
      }
    });
  }

  Future<Uint8List> _download(CachedRemoteImage key) async {
    final uri = Uri.parse(key.url);
    final client = http.Client();
    try {
      final response = await client.get(uri).timeout(_timeout);
      if (response.statusCode != 200) {
        throw http.ClientException('HTTP ${response.statusCode}', uri);
      }
      return shrink(response.bodyBytes, key.storedSize);
    } finally {
      client.close();
    }
  }

  static Future<bool> _isFresh(File file) async {
    if (!file.existsSync()) return false;
    try {
      return DateTime.now().difference(await file.lastModified()) < _maxAge;
    } on FileSystemException {
      return false;
    }
  }

  static Future<File> _fileFor(CachedRemoteImage key) async {
    final directory = _directory ??= await _open();
    final name = sha1
        .convert(utf8.encode('${key.storedSize}:${key.url}'))
        .toString();
    return File('${directory.path}/$name');
  }

  static Future<Directory> _open() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}/cache/images');
    await directory.create(recursive: true);
    return directory;
  }

  /// [raw] re-encoded so its longest side is at most [longestSide]. Images
  /// already that small are returned untouched rather than re-encoded, which
  /// would cost time and lose nothing but quality.
  @visibleForTesting
  static Future<Uint8List> shrink(Uint8List raw, int longestSide) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(raw);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final wider = descriptor.width >= descriptor.height;
    if (descriptor.width <= longestSide && descriptor.height <= longestSide) {
      buffer.dispose();
      return raw;
    }
    final ui.Codec codec;
    try {
      codec = await descriptor.instantiateCodec(
        targetWidth: wider ? longestSide : null,
        targetHeight: wider ? null : longestSide,
      );
    } finally {
      buffer.dispose();
    }
    final frame = await codec.getNextFrame();
    try {
      final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) throw const FormatException('image would not re-encode');
      return png.buffer.asUint8List();
    } finally {
      frame.image.dispose();
      codec.dispose();
    }
  }

  @override
  bool operator ==(Object other) =>
      other is CachedRemoteImage &&
      other.url == url &&
      other.storedSize == storedSize;

  @override
  int get hashCode => Object.hash(url, storedSize);

  @override
  String toString() => 'CachedRemoteImage("$url", storedSize: $storedSize)';
}

/// Lets at most [_limit] operations run at once, queueing the rest.
class _Gate {
  _Gate(this._limit);

  final int _limit;
  final List<Completer<void>> _waiting = <Completer<void>>[];
  int _running = 0;

  Future<T> run<T>(Future<T> Function() action) async {
    if (_running >= _limit) {
      final turn = Completer<void>();
      _waiting.add(turn);
      await turn.future;
    }
    _running++;
    try {
      return await action();
    } finally {
      _running--;
      if (_waiting.isNotEmpty) _waiting.removeAt(0).complete();
    }
  }
}
