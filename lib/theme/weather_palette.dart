import 'package:flutter/material.dart';

/// Illustration colours are independent of the app's interface colour scheme:
/// a night sky describes the campus time, not the device's dark-mode setting.
@immutable
class WeatherPalette {
  const WeatherPalette({
    required this.skyTop,
    required this.skyBottom,
    required this.ink,
    required this.cloud,
    required this.distant,
    required this.ground,
    required this.leaf,
    required this.building,
    required this.buildingSide,
    required this.window,
    required this.path,
    required this.celestial,
  });

  final Color skyTop;
  final Color skyBottom;
  final Color ink;
  final Color cloud;
  final Color distant;
  final Color ground;
  final Color leaf;
  final Color building;
  final Color buildingSide;
  final Color window;
  final Color path;
  final Color celestial;

  Gradient get sky => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[skyTop, skyBottom],
  );

  static const day = WeatherPalette(
    skyTop: Color(0xFFCEEBF2),
    skyBottom: Color(0xFFF0F3DC),
    ink: Color(0xFF203E49),
    cloud: Color(0xFFFAFCF6),
    distant: Color(0xFFA4BDAA),
    ground: Color(0xFF759C7C),
    leaf: Color(0xFF386E59),
    building: Color(0xFFF2E6CF),
    buildingSide: Color(0xFFC7BAA5),
    window: Color(0xFF5A7980),
    path: Color(0xFFDFD7BC),
    celestial: Color(0xFFFFCE64),
  );

  static const overcast = WeatherPalette(
    skyTop: Color(0xFFD2DFE4),
    skyBottom: Color(0xFFE8EDE5),
    ink: Color(0xFF293F4B),
    cloud: Color(0xFFF3F6F4),
    distant: Color(0xFFA7B8B0),
    ground: Color(0xFF7E9C88),
    leaf: Color(0xFF4F7769),
    building: Color(0xFFEAE4D6),
    buildingSide: Color(0xFFB7B9AE),
    window: Color(0xFF637F89),
    path: Color(0xFFD2D1BE),
    celestial: Color(0xFFE5D6AC),
  );

  static const rain = WeatherPalette(
    skyTop: Color(0xFFB8CED8),
    skyBottom: Color(0xFFD8E3DC),
    ink: Color(0xFF203B4A),
    cloud: Color(0xFF95AFBE),
    distant: Color(0xFF91AAA5),
    ground: Color(0xFF658A79),
    leaf: Color(0xFF355F55),
    building: Color(0xFFD5D8D0),
    buildingSide: Color(0xFF9CAFAE),
    window: Color(0xFF516E7D),
    path: Color(0xFFB9C7C6),
    celestial: Color(0xFFFBE6A3),
  );

  static const twilight = WeatherPalette(
    skyTop: Color(0xFFD6D6E9),
    skyBottom: Color(0xFFF8D4B2),
    ink: Color(0xFF3D354C),
    cloud: Color(0xFFF5E5DB),
    distant: Color(0xFFA3A4AE),
    ground: Color(0xFF788F89),
    leaf: Color(0xFF4E6A67),
    building: Color(0xFFECD6BD),
    buildingSide: Color(0xFFB6A7A0),
    window: Color(0xFFEABC7F),
    path: Color(0xFFCCBFB0),
    celestial: Color(0xFFFFB773),
  );

  static const night = WeatherPalette(
    skyTop: Color(0xFF182C46),
    skyBottom: Color(0xFF496377),
    ink: Color(0xFFF1F3EC),
    cloud: Color(0xFF52677F),
    distant: Color(0xFF425E65),
    ground: Color(0xFF344E4F),
    leaf: Color(0xFF233D42),
    building: Color(0xFF819191),
    buildingSide: Color(0xFF53686F),
    window: Color(0xFFF0D49B),
    path: Color(0xFF6A7D80),
    celestial: Color(0xFFF5EDD2),
  );

  static const snow = WeatherPalette(
    skyTop: Color(0xFFD9E5EF),
    skyBottom: Color(0xFFF3F5F4),
    ink: Color(0xFF304354),
    cloud: Color(0xFFFAFCFD),
    distant: Color(0xFFC0CDD3),
    ground: Color(0xFFE5EDED),
    leaf: Color(0xFF73938E),
    building: Color(0xFFF7F1E6),
    buildingSide: Color(0xFFC1CCD0),
    window: Color(0xFF728C9C),
    path: Color(0xFFC5D4DC),
    celestial: Color(0xFFEDE4C4),
  );
}
