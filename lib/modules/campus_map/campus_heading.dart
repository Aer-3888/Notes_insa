import 'dart:io';

import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One compass sample. [accuracyDegrees] is the error the platform claims,
/// null when it will not say.
class CampusHeading {
  const CampusHeading({
    required this.degrees,
    this.accuracyDegrees,
    this.isTrueNorth = false,
  });

  static const CampusHeading unavailable = CampusHeading(degrees: null);

  final double? degrees;
  final double? accuracyDegrees;

  /// iOS resolves true north itself. Android reads the magnetometer, so its
  /// samples still need the local declination.
  final bool isTrueNorth;

  /// Android reports 45 when the magnetometer is disturbed, iOS a measured
  /// error. Past that the map would point at the wrong building.
  bool get isCoarse => (accuracyDegrees ?? 0) >= 45;
}

abstract interface class CampusHeadingSource {
  Stream<CampusHeading> watch();
}

class DeviceCampusHeadingSource implements CampusHeadingSource {
  const DeviceCampusHeadingSource();

  @override
  Stream<CampusHeading> watch() {
    final events = FlutterCompass.events;
    if (events == null) {
      return Stream<CampusHeading>.value(CampusHeading.unavailable);
    }
    final trueNorth = Platform.isIOS;
    return events.map((event) {
      final degrees = event.heading;
      // CoreLocation sends exactly -1 when it cannot resolve true north,
      // which it cannot while nothing holds a location fix.
      if (trueNorth && degrees == -1) return CampusHeading.unavailable;
      return CampusHeading(
        degrees: degrees,
        accuracyDegrees: event.accuracy?.abs(),
        isTrueNorth: trueNorth,
      );
    });
  }
}

final campusHeadingSourceProvider = Provider<CampusHeadingSource>(
  (ref) => const DeviceCampusHeadingSource(),
);
