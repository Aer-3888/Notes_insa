import 'package:flutter/material.dart';

import '../../theme/campus_context.dart';
import '../../theme/tokens.dart';
import 'weather_advice.dart';
import 'weather_format.dart';
import 'weather_icons.dart';
import 'weather_model.dart';

/// The weather page without its plumbing: everything it draws comes from the
/// arguments, so it renders the same in a test as it does offline.
class WeatherBody extends StatelessWidget {
  const WeatherBody({
    super.key,
    required this.snapshot,
    required this.now,
    required this.freshness,
  });

  final WeatherSnapshot snapshot;
  final DateTime now;
  final String freshness;

  @override
  Widget build(BuildContext context) {
    final hours = upcomingHours(snapshot, now);
    final notes = weatherNotes(snapshot, now);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: CampusSpacing.x4),
      children: <Widget>[
        _Header(snapshot: snapshot, now: now),
        if (notes.isNotEmpty) ...<Widget>[
          const _Hairline(),
          for (final note in notes) _NoteRow(note: note),
        ],
        if (hours.isNotEmpty) ...<Widget>[
          const _Hairline(),
          _HourlyStrip(hours: hours),
        ],
        const _Hairline(),
        _Details(snapshot: snapshot),
        const _Hairline(),
        _Footer(freshness: freshness),
      ],
    );
  }
}

/// The home row: one line of weather that opens the page.
class WeatherStripView extends StatelessWidget {
  const WeatherStripView({
    super.key,
    required this.snapshot,
    required this.now,
    this.onTap,
  });

  final WeatherSnapshot snapshot;
  final DateTime now;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: CampusSpacing.gutter,
          vertical: CampusSpacing.x3,
        ),
        child: Row(
          children: <Widget>[
            Icon(
              weatherIcon(snapshot.weatherCode),
              size: 20,
              color: context.scheme.onSurfaceVariant,
            ),
            const SizedBox(width: CampusSpacing.x3),
            Text(
              temperatureLabel(snapshot.temperatureC),
              style: context.campusType.numeral,
            ),
            const SizedBox(width: CampusSpacing.x3),
            Expanded(
              child: Text(
                weatherPhrase(snapshot, now),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.bodyMedium?.copyWith(
                  color: context.scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.snapshot, required this.now});

  final WeatherSnapshot snapshot;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final muted = context.text.bodyMedium?.copyWith(
      color: context.scheme.onSurfaceVariant,
    );
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: CampusSpacing.gutter),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Wrap(
              spacing: CampusSpacing.x4,
              runSpacing: CampusSpacing.x2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                Icon(
                  weatherIcon(snapshot.weatherCode),
                  size: 32,
                  color: context.scheme.onSurfaceVariant,
                ),
                Text(
                  temperatureLabel(snapshot.temperatureC),
                  semanticsLabel: spokenDegrees(snapshot.temperatureC),
                  style: context.campusType.displayNumeral,
                ),
              ],
            ),
            const SizedBox(height: CampusSpacing.x2),
            Text(weatherPhrase(snapshot, now), style: context.text.titleMedium),
            const SizedBox(height: CampusSpacing.x1),
            Text(
              'Ressenti ${degreesLabel(snapshot.apparentTemperatureC)}, '
              'de ${degreesLabel(snapshot.low)} '
              'à ${degreesLabel(snapshot.high)} aujourd’hui',
              style: muted,
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteRow extends StatelessWidget {
  const _NoteRow({required this.note});

  final WeatherNote note;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: CampusSpacing.gutter,
          vertical: CampusSpacing.x2,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              noteIcon(note.kind),
              size: 20,
              color: context.scheme.onSurfaceVariant,
            ),
            const SizedBox(width: CampusSpacing.x3),
            Expanded(child: Text(note.text, style: context.text.bodyLarge)),
          ],
        ),
      ),
    );
  }
}

class _HourlyStrip extends StatelessWidget {
  const _HourlyStrip({required this.hours});

  final List<HourlyPoint> hours;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Prévisions heure par heure',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: CampusSpacing.gutter),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[for (final hour in hours) _HourColumn(hour: hour)],
        ),
      ),
    );
  }
}

class _HourColumn extends StatelessWidget {
  const _HourColumn({required this.hour});

  final HourlyPoint hour;

  /// Below this a rain chance is noise, not information.
  static const int _worthShowing = 20;

  String get _spoken {
    final rain = hour.precipitationProbability >= _worthShowing
        ? ', ${percentLabel(hour.precipitationProbability)} de risque de pluie'
        : '';
    return '${hourLabel(hour.time)}, ${spokenDegrees(hour.temperatureC)}$rain';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Semantics(
      container: true,
      label: _spoken,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(right: CampusSpacing.x5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              hourLabel(hour.time),
              style: context.text.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: CampusSpacing.x2),
            Icon(
              weatherIcon(hour.weatherCode),
              size: 20,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: CampusSpacing.x2),
            Text(
              degreesLabel(hour.temperatureC),
              style: context.campusType.numeral,
            ),
            if (hour.precipitationProbability >= _worthShowing) ...<Widget>[
              const SizedBox(height: CampusSpacing.x1),
              Text(
                percentLabel(hour.precipitationProbability),
                style: context.text.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.snapshot});

  final WeatherSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        _DetailRow(
          label: 'Lever',
          value: clockLabel(snapshot.sunrise),
          spoken: spokenClock(snapshot.sunrise),
        ),
        _DetailRow(
          label: 'Coucher',
          value: clockLabel(snapshot.sunset),
          spoken: spokenClock(snapshot.sunset),
        ),
        _DetailRow(
          label: 'Vent',
          value: '${snapshot.windSpeedKmh.round()}${nbsp}km/h',
          spoken: '${snapshot.windSpeedKmh.round()} kilomètres par heure',
        ),
        _DetailRow(
          label: 'Indice UV',
          value: snapshot.uvIndexMax.round().toString(),
        ),
        if (snapshot.precipitationSumMm > 0)
          _DetailRow(
            label: 'Précipitations',
            value: millimetresLabel(snapshot.precipitationSumMm),
          ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value, this.spoken});

  final String label;
  final String value;
  final String? spoken;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: CampusSpacing.gutter,
          vertical: CampusSpacing.x2,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                style: context.text.bodyMedium?.copyWith(
                  color: context.scheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: CampusSpacing.x4),
            Text(
              value,
              semanticsLabel: spoken,
              style: context.campusType.numeral,
            ),
          ],
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.freshness});

  final String freshness;

  @override
  Widget build(BuildContext context) {
    final style = context.text.labelMedium?.copyWith(
      color: context.scheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: CampusSpacing.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(freshness, style: style),
          const SizedBox(height: CampusSpacing.x1),
          Text('Données Open-Meteo', style: style),
        ],
      ),
    );
  }
}

class _Hairline extends StatelessWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context) => Divider(
    height: CampusSpacing.x8,
    thickness: 1,
    color: context.scheme.outlineVariant,
  );
}
