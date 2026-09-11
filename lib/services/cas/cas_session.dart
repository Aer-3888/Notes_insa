import 'dart:convert';

import 'cookie_jar.dart';

/// A CAS session in the envelope the native `ExportCAS` / `ImportCAS` use:
/// `{"version":1,"cookies":{<url>:[{"Name":..,"Value":..}]}}`.
///
/// Field names are capitalised because the Go side decodes into `http.Cookie`.
class CasSession {
  static const int version = 1;

  static String export(CookieJar jar, List<String> hosts) {
    final cookies = <String, List<Map<String, String>>>{};

    for (final host in hosts) {
      cookies[host] = jar
          .cookiesFor(Uri.parse(host))
          .map(
            (StoredCookie c) => <String, String>{
              'Name': c.name,
              'Value': c.value,
            },
          )
          .toList();
    }

    return jsonEncode(<String, dynamic>{
      'version': version,
      'cookies': cookies,
    });
  }

  /// Throws [FormatException] on anything unreadable, so the caller falls back
  /// to a full sign-in instead of a half-restored session.
  static void import(CookieJar jar, String serialized) {
    final Object? decoded = jsonDecode(serialized);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('CAS session is not an object');
    }

    if (decoded['version'] != version) {
      throw FormatException(
        'unsupported CAS session version ${decoded['version']}',
      );
    }

    final Object? cookies = decoded['cookies'];
    if (cookies is! Map<String, dynamic>) {
      throw const FormatException('CAS session has no cookie map');
    }

    for (final entry in cookies.entries) {
      final uri = Uri.parse(entry.key);
      final Object? list = entry.value;
      if (list is! List) continue;

      for (final Object? item in list) {
        if (item is! Map<String, dynamic>) continue;
        final Object? name = item['Name'];
        final Object? value = item['Value'];
        if (name is String && value is String && name.isNotEmpty) {
          jar.storeNameValue(uri, name, value);
        }
      }
    }
  }
}
