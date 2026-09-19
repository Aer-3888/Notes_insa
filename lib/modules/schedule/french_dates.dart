/// The module's one French date vocabulary.
const List<String> frenchWeekdays = <String>[
  'lundi',
  'mardi',
  'mercredi',
  'jeudi',
  'vendredi',
  'samedi',
  'dimanche',
];

const List<String> frenchWeekdaysShort = <String>[
  'lun',
  'mar',
  'mer',
  'jeu',
  'ven',
  'sam',
  'dim',
];

const List<String> frenchMonths = <String>[
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];

String frenchDayLabel(DateTime d) =>
    '${frenchWeekdays[d.weekday - 1]} ${d.day} ${frenchMonths[d.month - 1]}';

/// Day and month alone, to name one session without the weekday.
String frenchDayMonth(DateTime d) => '${d.day} ${frenchMonths[d.month - 1]}';
