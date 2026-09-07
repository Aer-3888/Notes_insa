import 'package:flutter/material.dart';

import '../../theme/campus_context.dart';
import '../../theme/tokens.dart';
import 'weather_advice.dart';
import 'weather_format.dart';
import 'weather_icons.dart';
import 'weather_model.dart';
import 'weather_scene.dart';

/// The page without its plumbing: everything it draws is an argument.
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
    final phrase = weatherPhrase(snapshot, now);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            CampusSpacing.gutter,
            CampusSpacing.x2,
            CampusSpacing.gutter,
            CampusSpacing.x8,
          ),
          children: <Widget>[
            _Header(snapshot: snapshot, now: now, freshness: freshness),
            if (notes.isNotEmpty ||
                phrase != conditionLabel(snapshot.weatherCode)) ...<Widget>[
              const SizedBox(height: CampusSpacing.x4),
              _WeatherSection(
                title: 'Pour votre journée',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: CampusSpacing.x4,
                      ),
                      child: Text(phrase, style: context.text.bodyLarge),
                    ),
                    if (notes.isNotEmpty)
                      const SizedBox(height: CampusSpacing.x2),
                    for (final note in notes) _NoteRow(note: note),
                  ],
                ),
              ),
            ],
            if (hours.isNotEmpty) ...<Widget>[
              const SizedBox(height: CampusSpacing.x3),
              _WeatherSection(
                title: 'Les prochaines heures',
                child: _HourlyStrip(hours: hours, snapshot: snapshot, now: now),
              ),
            ],
            const SizedBox(height: CampusSpacing.x3),
            _WeatherSection(
              title: 'Aujourd’hui en détail',
              child: _Details(snapshot: snapshot),
            ),
            const SizedBox(height: CampusSpacing.x5),
            const _Footer(),
          ],
        ),
      ),
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
              weatherIcon(
                snapshot.weatherCode,
                isNight: WeatherSceneData.fromSnapshot(snapshot, now).isNight,
              ),
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
  const _Header({
    required this.snapshot,
    required this.now,
    required this.freshness,
  });

  final WeatherSnapshot snapshot;
  final DateTime now;
  final String freshness;

  @override
  Widget build(BuildContext context) {
    final scene = WeatherSceneData.fromSnapshot(snapshot, now);
    final ink = scene.palette.ink;
    return LayoutBuilder(
      builder: (context, constraints) => ClipRRect(
        borderRadius: CampusRadii.cardRadius,
        child: Stack(
          children: <Widget>[
            Positioned.fill(child: WeatherScene(data: scene)),
            Padding(
              padding: EdgeInsets.fromLTRB(
                CampusSpacing.x6,
                CampusSpacing.x6,
                CampusSpacing.x6,
                constraints.maxWidth * .46 + CampusSpacing.x4,
              ),
              child: MergeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Rennes · Beaulieu',
                      style: context.text.titleSmall?.copyWith(color: ink),
                    ),
                    const SizedBox(height: CampusSpacing.x1),
                    Text(
                      freshness,
                      style: context.text.labelMedium?.copyWith(color: ink),
                    ),
                    const SizedBox(height: CampusSpacing.x4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        degreesLabel(snapshot.temperatureC),
                        semanticsLabel: spokenDegrees(snapshot.temperatureC),
                        style: context.campusType.displayNumeral.copyWith(
                          fontSize: 80,
                          height: 1.05,
                          fontWeight: FontWeight.w300,
                          fontVariations: const <FontVariation>[
                            FontVariation.weight(300),
                          ],
                          letterSpacing: -4,
                          color: ink,
                        ),
                      ),
                    ),
                    const SizedBox(height: CampusSpacing.x2),
                    Text(
                      conditionLabel(snapshot.weatherCode),
                      style: context.text.titleLarge?.copyWith(color: ink),
                    ),
                    const SizedBox(height: CampusSpacing.x2),
                    Text(
                      'Ressenti ${degreesLabel(snapshot.apparentTemperatureC)}',
                      style: context.text.bodyMedium?.copyWith(color: ink),
                    ),
                    const SizedBox(height: CampusSpacing.x1),
                    Text(
                      'Min. ${degreesLabel(snapshot.low)}  ·  Max. ${degreesLabel(snapshot.high)}',
                      style: context.text.bodyMedium?.copyWith(color: ink),
                    ),
                  ],
                ),
              ),
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
  const _HourlyStrip({
    required this.hours,
    required this.snapshot,
    required this.now,
  });

  final List<HourlyPoint> hours;
  final WeatherSnapshot snapshot;
  final DateTime now;

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
          children: <Widget>[
            for (var i = 0; i < hours.length; i++)
              _HourColumn(
                hour: hours[i],
                isCurrent:
                    !hours[i].time.isAfter(now) &&
                    hours[i].time.add(const Duration(hours: 1)).isAfter(now),
                isNight: WeatherSceneData.fromSnapshot(
                  snapshot,
                  hours[i].time,
                ).isNight,
              ),
          ],
        ),
      ),
    );
  }
}

class _HourColumn extends StatelessWidget {
  const _HourColumn({
    required this.hour,
    required this.isNight,
    required this.isCurrent,
  });

  final HourlyPoint hour;
  final bool isNight;
  final bool isCurrent;

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
      child: Container(
        margin: const EdgeInsets.only(right: CampusSpacing.x2),
        padding: const EdgeInsets.symmetric(
          horizontal: CampusSpacing.x3,
          vertical: CampusSpacing.x2,
        ),
        decoration: BoxDecoration(
          color: isCurrent ? context.campus.nowContainer : Colors.transparent,
          borderRadius: CampusRadii.controlRadius,
        ),
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
              weatherIcon(hour.weatherCode, isNight: isNight),
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
  const _Footer();

  @override
  Widget build(BuildContext context) {
    final style = context.text.labelMedium?.copyWith(
      color: context.scheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: CampusSpacing.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[Text('Données Open-Meteo', style: style)],
      ),
    );
  }
}

class _WeatherSection extends StatelessWidget {
  const _WeatherSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.scheme.brightness == Brightness.dark
          ? context.scheme.surfaceContainer
          : context.scheme.surfaceContainerLowest,
      borderRadius: CampusRadii.cardRadius,
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: CampusSpacing.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              CampusSpacing.x4,
              0,
              CampusSpacing.x4,
              CampusSpacing.x3,
            ),
            child: Text(title, style: context.text.titleSmall),
          ),
          child,
        ],
      ),
    ),
  );
}
