/// French copy keeps the gap before a unit non-breaking.
const String nbsp = ' ';

/// Rounds away from a negative zero, which reads as a typo at 0 °.
int _round(double celsius) {
  final rounded = celsius.round();
  return rounded == 0 ? 0 : rounded;
}

String temperatureLabel(double celsius) => '${_round(celsius)}$nbsp°C';

String degreesLabel(double celsius) => '${_round(celsius)}$nbsp°';

String percentLabel(int percent) => '$percent$nbsp%';

String millimetresLabel(double mm) =>
    '${mm.toStringAsFixed(1).replaceAll('.', ',')}${nbsp}mm';

String hourLabel(DateTime time) => '${time.hour}${nbsp}h';

/// Screen readers get words, not glyphs: `15 °` is read as "quinze degré
/// signe" by TalkBack unless the label spells it out.
String spokenDegrees(double celsius) {
  final rounded = _round(celsius);
  final unit = rounded.abs() <= 1 ? 'degré' : 'degrés';
  return '$rounded $unit';
}

String spokenClock(DateTime time) =>
    '${time.hour} h ${time.minute.toString().padLeft(2, '0')}';

String clockLabel(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}';
