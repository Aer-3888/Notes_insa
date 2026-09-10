import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

enum CampusLocationFailure {
  serviceDisabled,
  denied,
  deniedForever,
  unavailable,
}

class CampusLocationException implements Exception {
  const CampusLocationException(this.failure);

  final CampusLocationFailure failure;
}

class CampusPosition {
  const CampusPosition({
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
  });

  final double latitude;
  final double longitude;

  /// Radius the platform claims the fix is good to, drawn as the halo under
  /// the marker. Null when it will not say.
  final double? accuracyMeters;
}

abstract interface class CampusLocationSource {
  Future<CampusPosition> current();

  Stream<CampusPosition> watch();
}

class DeviceCampusLocationSource implements CampusLocationSource {
  const DeviceCampusLocationSource();

  @override
  Future<CampusPosition> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const CampusLocationException(
        CampusLocationFailure.serviceDisabled,
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const CampusLocationException(CampusLocationFailure.deniedForever);
    }
    if (permission == LocationPermission.denied) {
      throw const CampusLocationException(CampusLocationFailure.denied);
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return CampusPosition(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
      );
    } on CampusLocationException {
      rethrow;
    } catch (_) {
      throw const CampusLocationException(CampusLocationFailure.unavailable);
    }
  }

  @override
  Stream<CampusPosition> watch() =>
      Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          // Two metres, so the marker walks instead of hopping between
          // building corners.
          distanceFilter: 2,
        ),
      ).map(
        (position) => CampusPosition(
          latitude: position.latitude,
          longitude: position.longitude,
          accuracyMeters: position.accuracy,
        ),
      );
}

final campusLocationSourceProvider = Provider<CampusLocationSource>(
  (ref) => const DeviceCampusLocationSource(),
);
