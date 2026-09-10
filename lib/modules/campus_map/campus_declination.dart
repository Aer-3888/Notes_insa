import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Degrees to add to a magnetic heading to read as true north, which is what
/// the baked campus geometry is drawn in.
abstract interface class CampusDeclinationSource {
  Future<double> at(double latitude, double longitude);
}

class DeviceCampusDeclinationSource implements CampusDeclinationSource {
  const DeviceCampusDeclinationSource();

  static const MethodChannel _channel = MethodChannel(
    'com.aer.notes_insa/campus_map',
  );

  @override
  Future<double> at(double latitude, double longitude) async {
    if (!Platform.isAndroid) return 0;
    try {
      final degrees = await _channel.invokeMethod<double>(
        'MagneticDeclination',
        <String, double>{'latitude': latitude, 'longitude': longitude},
      );
      return degrees ?? 0;
    } on PlatformException {
      return 0;
    } on MissingPluginException {
      return 0;
    }
  }
}

final campusDeclinationSourceProvider = Provider<CampusDeclinationSource>(
  (ref) => const DeviceCampusDeclinationSource(),
);
