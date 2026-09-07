import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/freshness.dart';
import '../../core/module_cache.dart';
import '../../core/time.dart';
import '../../theme/state_view.dart';
import 'weather_body.dart';
import 'weather_provider.dart';

/// One line of weather on Aujourd'hui. Shows nothing until there is a snapshot,
/// so the home screen never reserves space for an empty row.
class WeatherStrip extends ConsumerWidget {
  const WeatherStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(weatherProvider).value?.data;
    if (snapshot == null) return const SizedBox.shrink();
    return WeatherStripView(
      snapshot: snapshot,
      now: campusNow(),
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const WeatherScreen())),
    );
  }
}

class WeatherScreen extends ConsumerStatefulWidget {
  const WeatherScreen({super.key});

  @override
  ConsumerState<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends ConsumerState<WeatherScreen>
    with WidgetsBindingObserver {
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startClock();
  }

  void _startClock() {
    _clock?.cancel();
    // Update solar lighting, hourly forecasts and freshness while open.
    // This only rebuilds the view; it does not make a weather request.
    _clock = Timer.periodic(const Duration(minutes: 1), (_) => setState(() {}));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startClock();
      setState(() {});
    } else {
      _clock?.cancel();
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(weatherProvider);
    await ref.read(weatherProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(weatherProvider);
    final entry = async.value;
    final snapshot = entry?.data;

    final Widget body;
    if (snapshot != null) {
      body = WeatherBody(
        snapshot: snapshot,
        now: campusNow(),
        freshness: freshnessLabel(entry!.refreshState, entry.cachedAt),
      );
    } else if (async.isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = StateView(
        icon: Icons.cloud_off_outlined,
        title: 'Météo indisponible',
        body: _why(entry?.refreshState),
        action: FilledButton.tonalIcon(
          onPressed: () => ref.invalidate(weatherProvider),
          icon: const Icon(Icons.refresh),
          label: const Text('Réessayer'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Météo')),
      body: RefreshIndicator(onRefresh: () => _refresh(ref), child: body),
    );
  }
}

/// Offline and "the service is broken" need different words: one of them the
/// student can act on.
String _why(RefreshState? state) => switch (state) {
  RefreshState.failedOffline =>
    'Vous êtes hors ligne. La météo revient dès que la connexion est '
        'rétablie.',
  _ => 'Le service météo ne répond pas. Réessayez dans un moment.',
};
