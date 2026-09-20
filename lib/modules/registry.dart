import 'package:flutter/material.dart';

import 'associations/associations_screen.dart';
import 'campus_map/map_screen.dart';
import 'grades/dashboard_screen.dart';
import 'grades/two_factor_screen.dart';
import 'laundry/laundry_screen.dart';
import 'rooms/rooms_screen.dart';
import 'schedule/schedule_screen.dart';
import 'weather/weather_screen.dart';

/// One entry in the campus hub. Sealed so the hub's switch is exhaustive and a
/// new kind cannot be added without every call site being updated.
sealed class CampusModule {
  const CampusModule({
    required this.id,
    required this.label,
    required this.icon,
    String? shortLabel,
  }) : _shortLabel = shortLabel;

  final String id;
  final String label;
  final IconData icon;

  final String? _shortLabel;

  /// Label for the bottom bar, where five destinations leave about 72 dp each.
  /// Falls back to [label] when it already fits.
  String get barLabel => _shortLabel ?? label;
}

/// A module with an implementation behind it. Every module in the registry is
/// one of these: unbuilt modules do not appear in the UI.
final class ReadyModule extends CampusModule {
  const ReadyModule({
    required super.id,
    required super.label,
    required super.icon,
    required this.builder,
    super.shortLabel,
    this.requiresCas = false,
  });

  final WidgetBuilder builder;

  /// True when opening this module requires INSA credentials and the lock.
  final bool requiresCas;
}

const List<CampusModule> kCampusModules = <CampusModule>[
  ReadyModule(
    id: 'edt',
    label: 'Emploi du temps',
    shortLabel: 'Cours',
    icon: Icons.calendar_month_outlined,
    builder: _schedule,
  ),
  ReadyModule(
    id: 'notes',
    label: 'Notes',
    icon: Icons.school_outlined,
    requiresCas: true,
    builder: _gradesDashboard,
  ),
  ReadyModule(
    id: 'meteo',
    label: 'Météo',
    icon: Icons.wb_sunny_outlined,
    builder: _weather,
  ),
  ReadyModule(
    id: 'carte',
    label: 'Carte',
    icon: Icons.map_outlined,
    builder: _map,
  ),
  ReadyModule(
    id: 'salles',
    label: 'Salles libres',
    shortLabel: 'Salles',
    icon: Icons.meeting_room_outlined,
    builder: _rooms,
  ),
  ReadyModule(
    id: 'assos',
    label: 'Associations',
    shortLabel: 'Assos',
    icon: Icons.groups_outlined,
    builder: _associations,
  ),
  ReadyModule(
    id: 'laverie',
    label: 'Laverie',
    icon: Icons.local_laundry_service_outlined,
    builder: _laundry,
  ),
];

Widget _schedule(BuildContext context) => const ScheduleScreen();

Widget _weather(BuildContext context) => const WeatherScreen();

Widget _map(BuildContext context) => const MapScreen();

Widget _rooms(BuildContext context) => const RoomsScreen();

Widget _laundry(BuildContext context) => const LaundryScreen();

Widget _associations(BuildContext context) => const AssociationsScreen();

Widget _gradesDashboard(BuildContext context) => DashboardScreen(
  onReauthRequired: () => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const TwoFactorScreen())),
);
