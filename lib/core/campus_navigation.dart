import 'package:flutter/material.dart';

/// A request to show a building on the campus map.
///
/// The revision makes a second request for the same building observable by a
/// map screen that is already open.
class CampusMapFocus extends ChangeNotifier {
  String? _buildingCode;
  bool _startGuidance = false;
  int _revision = 0;

  String? get buildingCode => _buildingCode;
  bool get startGuidance => _startGuidance;
  int get revision => _revision;

  void request(String buildingCode, {bool startGuidance = false}) {
    _buildingCode = buildingCode;
    _startGuidance = startGuidance;
    _revision++;
    notifyListeners();
  }
}

typedef OpenCampusMap =
    void Function(String buildingCode, {bool startGuidance});

typedef CampusPlaceDetailsBuilder = Widget? Function(String placeCode);

/// Optional details supplied by another feature for a place on the map.
///
/// Keeping the builder at shell level lets the map display restaurant status
/// without coupling the map module to the CROUS module.
class CampusPlaceDetailsScope extends InheritedWidget {
  const CampusPlaceDetailsScope({
    super.key,
    required this.builder,
    required super.child,
  });

  final CampusPlaceDetailsBuilder builder;

  static CampusPlaceDetailsScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CampusPlaceDetailsScope>();

  @override
  bool updateShouldNotify(CampusPlaceDetailsScope oldWidget) =>
      builder != oldWidget.builder;
}

/// Shell navigation available to module screens.
///
/// It lets a module select a destination without pushing a second copy of the
/// destination above the bottom navigation bar.
class CampusNavigationScope extends InheritedNotifier<CampusMapFocus> {
  const CampusNavigationScope({
    super.key,
    required CampusMapFocus mapFocus,
    required this.onOpenMap,
    required super.child,
  }) : super(notifier: mapFocus);

  final OpenCampusMap onOpenMap;

  static CampusNavigationScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CampusNavigationScope>();
}
