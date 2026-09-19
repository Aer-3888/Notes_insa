import '../../core/time.dart';
import 'schedule_event.dart';

/// Parses the INSA Rennes ADE anonymous iCal export.
///
/// ADE's DESCRIPTION is semi-structured free text rather than named fields, so
/// the split below is a heuristic. Anything it cannot classify is dropped from
/// the structured fields rather than guessed at; the summary and room always
/// survive so an event is never rendered blank.
List<ScheduleEvent> parseAdeIcs(String source) {
  if (!source.contains('BEGIN:VCALENDAR')) {
    throw const FormatException('not an iCalendar payload');
  }

  final events = <ScheduleEvent>[];
  for (final block in _eventBlocks(_unfold(source))) {
    final fields = _fields(block);
    final start = _parseUtcStamp(fields['DTSTART']);
    final end = _parseUtcStamp(fields['DTEND']);
    if (start == null || end == null) continue;

    final parts = _describe(fields['DESCRIPTION'] ?? '');
    final room = _clean(fields['LOCATION']);
    final uid = _clean(fields['UID']);

    events.add(
      ScheduleEvent(
        title: _unescape(fields['SUMMARY'] ?? '').trim(),
        start: start,
        end: end,
        groups: parts.groups,
        teachers: parts.teachers,
        module: parts.module,
        room: room,
        uid: uid,
        activityId: adeActivityId(uid),
      ),
    );
  }

  events.sort((a, b) => a.start.compareTo(b.start));
  return events;
}

/// iCal folds long lines at 75 octets with a leading space or tab. Unfolding
/// has to happen before any line-based parsing or descriptions get truncated.
String _unfold(String source) => source.replaceAll(RegExp(r'\r?\n[ \t]'), '');

Iterable<String> _eventBlocks(String unfolded) => RegExp(
  r'BEGIN:VEVENT(.*?)END:VEVENT',
  dotAll: true,
).allMatches(unfolded).map((m) => m.group(1)!);

Map<String, String> _fields(String block) {
  final out = <String, String>{};
  for (final line in block.split(RegExp(r'\r?\n'))) {
    final match = RegExp(r'^([A-Z-]+)(?:;[^:]*)?:(.*)$').firstMatch(line);
    if (match != null) out[match.group(1)!] = match.group(2)!;
  }
  return out;
}

/// ADE stamps every time in UTC (`20260907T070000Z`). Converted to campus time
/// so comparisons and display both use Rennes wall-clock.
DateTime? _parseUtcStamp(String? raw) {
  if (raw == null) return null;
  final match = RegExp(
    r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z$',
  ).firstMatch(raw.trim());
  if (match == null) return null;
  final utc = DateTime.utc(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
    int.parse(match.group(6)!),
  );
  return campusFromEpochMs(utc.millisecondsSinceEpoch);
}

/// The course series [uid] belongs to, or null when it is not an ADE uid.
///
/// ADE writes a uid as a short prefix then the hex of an ASCII identifier:
/// `ADE60323032362d…` decodes to `2026-2027-5506-0-0`, whose third field is
/// the activity. Every session of a series carries the same one.
String? adeActivityId(String? uid) {
  if (uid == null) return null;
  // The prefix is itself valid hex, so every plausible start is tried.
  for (var start = 3; start <= 8 && start < uid.length; start++) {
    if ((uid.length - start) % 2 != 0) continue;
    final decoded = _fromHex(uid.substring(start));
    if (decoded == null) continue;
    final match = _adeIdentifier.firstMatch(decoded);
    if (match != null) return match.group(1);
  }
  return null;
}

/// `<year>-<year>-<activity>-<n>-<occurrence>`.
final RegExp _adeIdentifier = RegExp(r'^\d{4}-\d{4}-(\d+)-\d+-\d+$');

String? _fromHex(String hex) {
  final units = <int>[];
  for (var i = 0; i < hex.length; i += 2) {
    final byte = int.tryParse(hex.substring(i, i + 2), radix: 16);
    // Not the payload if it does not decode to printable ASCII.
    if (byte == null || byte < 0x20 || byte > 0x7e) return null;
    units.add(byte);
  }
  return String.fromCharCodes(units);
}

String _unescape(String v) => v
    .replaceAll(r'\n', '\n')
    .replaceAll(r'\,', ',')
    .replaceAll(r'\;', ';')
    .replaceAll(r'\\', r'\');

String? _clean(String? raw) {
  final v = _unescape(raw ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  return v.isEmpty ? null : v;
}

typedef _Described = ({
  List<String> groups,
  List<String> teachers,
  String? module,
});

/// Splits the DESCRIPTION block.
///
/// Shape is: group codes, then an optional module name, then teacher names,
/// then an export marker. Group codes start with `S<digit>-`; module names
/// contain lowercase letters and teacher names do not.
_Described _describe(String raw) {
  final groups = <String>[];
  final teachers = <String>[];
  final modules = <String>[];

  for (var line in _unescape(raw).split('\n')) {
    line = line.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('(Exported')) continue;
    // Co-taught sessions prefix additional teachers with "$$ - ".
    if (line.startsWith(r'$$')) {
      line = line.replaceFirst(RegExp(r'^\$\$\s*-\s*'), '').trim();
      if (line.isNotEmpty) teachers.add(line);
      continue;
    }
    if (RegExp(r'^S\d+-').hasMatch(line)) {
      groups.add(line);
    } else if (line.contains(RegExp('[a-z]'))) {
      modules.add(line);
    } else {
      teachers.add(line);
    }
  }

  return (
    groups: groups,
    teachers: teachers,
    module: modules.isEmpty ? null : modules.join(' '),
  );
}
