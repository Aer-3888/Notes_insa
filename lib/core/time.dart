import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Campus timezone. All schedule comparisons are made in this zone so a device
/// in another timezone still resolves "the next course" correctly.
const String kCampusTimezone = 'Europe/Paris';

tz.Location? _campus;

/// Loads the timezone database. Call once from main() before runApp.
Future<void> initCampusTime() async {
  tzdata.initializeTimeZones();
  _campus = tz.getLocation(kCampusTimezone);
}

tz.Location get _location {
  final loc = _campus;
  if (loc == null) {
    throw StateError('initCampusTime() must be called before campusNow()');
  }
  return loc;
}

/// Now, as wall-clock time on campus.
DateTime campusNow() => tz.TZDateTime.now(_location);

/// Rebuilds an instant as campus time.
///
/// Cached timestamps round-trip through epoch milliseconds rather than an ISO
/// string, because parsing an ISO string yields a device-local DateTime and
/// would show the viewer's hour instead of the campus hour.
DateTime campusFromEpochMs(int ms) =>
    tz.TZDateTime.fromMillisecondsSinceEpoch(_location, ms);

/// Reinterprets a naive wall-clock [local] as campus time.
///
/// Upstream campus APIs send times with no offset. This is how they become real
/// instants without being shifted by the device's own timezone.
DateTime campusInstant(DateTime local) => tz.TZDateTime(
  _location,
  local.year,
  local.month,
  local.day,
  local.hour,
  local.minute,
  local.second,
);
