import 'package:flutter/material.dart';

import 'grades/dashboard_screen.dart';
import 'grades/two_factor_screen.dart';
import 'weather/weather_screen.dart';

/// One entry in the campus hub. Sealed so the hub's switch is exhaustive and a
/// new state cannot be added without every call site being updated.
sealed class CampusModule {
  const CampusModule({
    required this.id,
    required this.label,
    required this.icon,
  });

  final String id;
  final String label;
  final IconData icon;
}

/// A module with an implementation behind it.
final class ReadyModule extends CampusModule {
  const ReadyModule({
    required super.id,
    required super.label,
    required super.icon,
    required this.builder,
    this.requiresCas = false,
  });

  final WidgetBuilder builder;

  /// True when opening this module requires INSA credentials and the lock.
  final bool requiresCas;
}

/// A module announced in the hub but not yet built.
final class ComingSoonModule extends CampusModule {
  const ComingSoonModule({
    required super.id,
    required super.label,
    required super.icon,
    required this.teaser,
  });

  final String teaser;
}

const List<CampusModule> kCampusModules = <CampusModule>[
  ReadyModule(
    id: 'edt',
    label: 'Emploi du temps',
    icon: Icons.calendar_month_outlined,
    builder: _notYetBuilt,
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
  ComingSoonModule(
    id: 'carte',
    label: 'Carte du campus',
    icon: Icons.map_outlined,
    teaser: 'Bâtiments, amphis et salles du campus de Beaulieu.',
  ),
  ComingSoonModule(
    id: 'assos',
    label: 'Événements et assos',
    icon: Icons.celebration_outlined,
    teaser: 'Les événements du campus, publiés par les assos.',
  ),
  ComingSoonModule(
    id: 'laverie',
    label: 'Laverie',
    icon: Icons.local_laundry_service_outlined,
    teaser: 'Machines libres en résidence, en temps réel.',
  ),
];

Widget _notYetBuilt(BuildContext context) =>
    const Scaffold(body: Center(child: Text('En cours de construction')));

Widget _weather(BuildContext context) => const WeatherScreen();

Widget _gradesDashboard(BuildContext context) => DashboardScreen(
  onReauthRequired: () => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const TwoFactorScreen())),
);
