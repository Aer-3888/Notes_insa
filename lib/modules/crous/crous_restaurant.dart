import 'package:flutter/foundation.dart';

enum CrousAvailability {
  open,
  opensLater,
  closed,
  publicHoliday,
  closedByCrous,
}

@immutable
class CrousRestaurantStatus {
  const CrousRestaurantStatus({
    required this.availability,
    required this.label,
    required this.detail,
    this.notice,
  });

  final CrousAvailability availability;
  final String label;
  final String detail;
  final String? notice;

  bool get isOpen => availability == CrousAvailability.open;
}

@immutable
class CrousOpeningPeriod {
  const CrousOpeningPeriod({
    required this.days,
    required this.opensAtMinute,
    required this.closesAtMinute,
  });

  /// ISO weekdays, Monday = 1 and Sunday = 7.
  final Set<int> days;
  final int opensAtMinute;
  final int closesAtMinute;

  String get usualHoursLabel =>
      '${crousDaysLabel(days)} · '
      '${crousClockLabel(opensAtMinute)}–${crousClockLabel(closesAtMinute)}';

  Map<String, dynamic> toJson() => <String, dynamic>{
    'days': days.toList()..sort(),
    'opensAtMinute': opensAtMinute,
    'closesAtMinute': closesAtMinute,
  };

  factory CrousOpeningPeriod.fromJson(Map<String, dynamic> json) {
    final rawDays = json['days'];
    if (rawDays is! List) throw const FormatException('days missing');
    return CrousOpeningPeriod(
      days: <int>{for (final day in rawDays) (day as num).toInt()},
      opensAtMinute: (json['opensAtMinute'] as num).toInt(),
      closesAtMinute: (json['closesAtMinute'] as num).toInt(),
    );
  }
}

@immutable
class CrousRestaurant {
  const CrousRestaurant({
    required this.id,
    required this.name,
    required this.shortName,
    required this.mapCode,
    required this.officialUrl,
    required this.declaredClosed,
    required this.openingPeriods,
    this.syncedAt,
  });

  final int id;
  final String name;
  final String shortName;
  final String mapCode;
  final String officialUrl;

  /// Live exceptional-closure flag published by the CROUS feed.
  final bool declaredClosed;

  final List<CrousOpeningPeriod> openingPeriods;
  final DateTime? syncedAt;

  CrousRestaurantStatus statusAt(DateTime now) {
    if (declaredClosed) {
      return const CrousRestaurantStatus(
        availability: CrousAvailability.closedByCrous,
        label: 'Fermé par le Crous',
        detail: 'Réouverture non annoncée',
      );
    }

    final date = DateTime.utc(now.year, now.month, now.day);
    final holiday = frenchPublicHolidayName(date);
    if (holiday != null) {
      return CrousRestaurantStatus(
        availability: CrousAvailability.publicHoliday,
        label: 'Fermé · jour férié',
        detail: '$holiday · ${_nextOpeningLabel(date)}',
      );
    }

    final minute = now.hour * 60 + now.minute;
    final notice = _tomorrowHolidayNotice(date);
    final periods = _periodsFor(date.weekday);
    for (final period in periods) {
      if (minute < period.opensAtMinute) {
        return CrousRestaurantStatus(
          availability: CrousAvailability.opensLater,
          label: 'Fermé pour le moment',
          detail: 'Ouvre à ${crousClockLabel(period.opensAtMinute)}',
          notice: notice,
        );
      }
      if (minute < period.closesAtMinute) {
        return CrousRestaurantStatus(
          availability: CrousAvailability.open,
          label: 'Ouvert',
          detail: 'Ferme à ${crousClockLabel(period.closesAtMinute)}',
          notice: notice,
        );
      }
    }

    return CrousRestaurantStatus(
      availability: CrousAvailability.closed,
      label: 'Fermé aujourd’hui',
      detail: _nextOpeningLabel(date),
      notice: notice,
    );
  }

  String? _tomorrowHolidayNotice(DateTime date) {
    final tomorrow = date.add(const Duration(days: 1));
    final holiday = frenchPublicHolidayName(tomorrow);
    return holiday == null ? null : 'Fermé demain · $holiday';
  }

  String _nextOpeningLabel(DateTime from) {
    for (var offset = 1; offset <= 14; offset++) {
      final day = from.add(Duration(days: offset));
      final periods = _periodsFor(day.weekday);
      if (periods.isEmpty) continue;
      if (frenchPublicHolidayName(day) != null) continue;
      final label = offset == 1 ? 'demain' : _weekday(day.weekday);
      return 'Ouvre $label à ${crousClockLabel(periods.first.opensAtMinute)}';
    }
    return 'Horaires à vérifier';
  }

  List<CrousOpeningPeriod> _periodsFor(int weekday) =>
      openingPeriods.where((period) => period.days.contains(weekday)).toList()
        ..sort(
          (left, right) => left.opensAtMinute.compareTo(right.opensAtMinute),
        );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'shortName': shortName,
    'mapCode': mapCode,
    'officialUrl': officialUrl,
    'declaredClosed': declaredClosed,
    'openingPeriods': <Map<String, dynamic>>[
      for (final period in openingPeriods) period.toJson(),
    ],
    'syncedAt': syncedAt?.toIso8601String(),
  };

  factory CrousRestaurant.fromJson(Map<String, dynamic> json) {
    final periods = json['openingPeriods'];
    if (periods is! List) {
      throw const FormatException('openingPeriods missing');
    }
    return CrousRestaurant(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      shortName: json['shortName'] as String,
      mapCode: json['mapCode'] as String,
      officialUrl: json['officialUrl'] as String,
      declaredClosed: json['declaredClosed'] as bool,
      openingPeriods: <CrousOpeningPeriod>[
        for (final period in periods)
          CrousOpeningPeriod.fromJson(
            Map<String, dynamic>.from(period as Map<dynamic, dynamic>),
          ),
      ],
      syncedAt: switch (json['syncedAt']) {
        final String value => DateTime.tryParse(value),
        // Reads caches from the first local implementation of this module.
        final num value => DateTime.fromMillisecondsSinceEpoch(
          value.toInt(),
          isUtc: true,
        ),
        _ => null,
      },
    );
  }
}

String crousClockLabel(int minute) {
  final hour = minute ~/ 60;
  final remainder = minute % 60;
  return remainder == 0
      ? '$hour h'
      : '$hour h ${remainder.toString().padLeft(2, '0')}';
}

String crousDaysLabel(Set<int> days) {
  const weekdays = <int>{1, 2, 3, 4, 5};
  const mondayToThursday = <int>{1, 2, 3, 4};
  if (days.length == weekdays.length && days.containsAll(weekdays)) {
    return 'Lun–ven';
  }
  if (days.length == mondayToThursday.length &&
      days.containsAll(mondayToThursday)) {
    return 'Lun–jeu';
  }
  const names = <int, String>{
    1: 'lun',
    2: 'mar',
    3: 'mer',
    4: 'jeu',
    5: 'ven',
    6: 'sam',
    7: 'dim',
  };
  final sorted = days.toList()..sort();
  return sorted.map((day) => names[day] ?? day.toString()).join(', ');
}

String _weekday(int weekday) => switch (weekday) {
  DateTime.monday => 'lundi',
  DateTime.tuesday => 'mardi',
  DateTime.wednesday => 'mercredi',
  DateTime.thursday => 'jeudi',
  DateTime.friday => 'vendredi',
  DateTime.saturday => 'samedi',
  _ => 'dimanche',
};

/// French mainland public holidays, including the three Easter-based dates.
String? frenchPublicHolidayName(DateTime date) {
  final fixed = <(int, int), String>{
    (1, 1): 'Jour de l’An',
    (5, 1): 'Fête du Travail',
    (5, 8): 'Victoire 1945',
    (7, 14): 'Fête nationale',
    (8, 15): 'Assomption',
    (11, 1): 'Toussaint',
    (11, 11): 'Armistice',
    (12, 25): 'Noël',
  };
  final fixedName = fixed[(date.month, date.day)];
  if (fixedName != null) return fixedName;

  final easter = _easterSunday(date.year);
  final offset = date.difference(easter).inDays;
  return switch (offset) {
    1 => 'Lundi de Pâques',
    39 => 'Ascension',
    50 => 'Lundi de Pentecôte',
    _ => null,
  };
}

DateTime _easterSunday(int year) {
  final a = year % 19;
  final b = year ~/ 100;
  final c = year % 100;
  final d = b ~/ 4;
  final e = b % 4;
  final f = (b + 8) ~/ 25;
  final g = (b - f + 1) ~/ 3;
  final h = (19 * a + b - d - g + 15) % 30;
  final i = c ~/ 4;
  final k = c % 4;
  final l = (32 + 2 * e + 2 * i - h - k) % 7;
  final m = (a + 11 * h + 22 * l) ~/ 451;
  final month = (h + l - 7 * m + 114) ~/ 31;
  final day = (h + l - 7 * m + 114) % 31 + 1;
  return DateTime.utc(year, month, day);
}
