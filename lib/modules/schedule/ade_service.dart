import 'package:http/http.dart' as http;

import 'ics_parser.dart';
import 'schedule_event.dart';

/// Reads the INSA Rennes ADE anonymous iCal export.
///
/// This is the school's own published export, so the app talks to it directly:
/// no credentials, no token, and no proxy tier. ADE windows the response
/// server-side via firstDate/lastDate, so no trimming is needed here.
class AdeService {
  const AdeService({http.Client? client}) : _client = client;

  final http.Client? _client;

  static const String origin = 'https://ade.insa-rennes.fr';
  static const String _path = '/jsp/custom/modules/plannings/anonymous_cal.jsp';

  /// ADE groups its data into per-year projects. 2 is the current one.
  static const int projectId = 2;

  /// Identify the app rather than impersonating a browser.
  static const Map<String, String> _headers = <String, String>{
    'User-Agent': 'CampusINSA/1.0 (+https://github.com/Aer-3888/Notes_insa)',
    'Accept': 'text/calendar',
  };

  static Uri buildUri({
    required List<int> resourceIds,
    required DateTime from,
    required DateTime to,
  }) => Uri.parse('$origin$_path').replace(
    queryParameters: <String, String>{
      'resources': resourceIds.join(','),
      'projectId': '$projectId',
      'calType': 'ical',
      'firstDate': _day(from),
      'lastDate': _day(to),
    },
  );

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<List<ScheduleEvent>> fetch({
    required List<int> resourceIds,
    required DateTime from,
    required DateTime to,
  }) async {
    if (resourceIds.isEmpty) return const <ScheduleEvent>[];
    final client = _client ?? http.Client();
    try {
      final uri = buildUri(resourceIds: resourceIds, from: from, to: to);
      final response = await client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw http.ClientException('HTTP ${response.statusCode}', uri);
      }
      return parseAdeIcs(response.body);
    } finally {
      if (_client == null) client.close();
    }
  }
}
