import 'package:flutter/material.dart';

import 'weather_advice.dart';

/// WMO code to icon. Outlined throughout, so the strip reads as one set.
IconData weatherIcon(int code) => switch (code) {
  0 || 1 => Icons.wb_sunny_outlined,
  2 => Icons.wb_cloudy_outlined,
  3 => Icons.cloud_outlined,
  45 || 48 => Icons.foggy,
  51 || 53 || 55 || 56 || 57 => Icons.water_drop_outlined,
  61 || 63 || 65 || 66 || 67 => Icons.water_drop_outlined,
  71 || 73 || 75 || 77 || 85 || 86 => Icons.ac_unit,
  80 || 81 || 82 => Icons.water_drop_outlined,
  95 || 96 || 99 => Icons.thunderstorm_outlined,
  _ => Icons.thermostat_outlined,
};

IconData noteIcon(WeatherNoteKind kind) => switch (kind) {
  WeatherNoteKind.umbrella => Icons.umbrella_outlined,
  WeatherNoteKind.coat => Icons.checkroom_outlined,
  WeatherNoteKind.wind => Icons.air_outlined,
  WeatherNoteKind.sun => Icons.wb_sunny_outlined,
};
