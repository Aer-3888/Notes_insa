import 'package:flutter/material.dart';

/// A request to show a building on the campus map.
///
/// The revision makes a second request for the same building observable by a
/// map screen that is already open.
class CampusMapFocus extends ChangeNotifier {
  String? _buildingCode;
  int _revision = 0;

  String? get buildingCode => _buildingCode;
  int get revision => _revision;

  void request(String buildingCode) {
    _buildingCode = buildingCode;
    _revision++;
    notifyListeners();
  }
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

  final ValueChanged<String> onOpenMap;

  static CampusNavigationScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CampusNavigationScope>();
}
