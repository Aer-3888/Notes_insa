import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/services/cas/cas_endpoints.dart';
import 'package:notes_insa/services/cas/cas_session.dart';
import 'package:notes_insa/services/cas/cookie_jar.dart';

void main() {
  const hosts = CasEndpoints.defaultSessionHosts;
  final cas = Uri.parse(hosts[0]);
  final mdw = Uri.parse(hosts[1]);

  CookieJar signedInJar() => CookieJar()
    ..storeAll(cas, <String>['JSESSIONID=cas-session; Path=/'])
    ..storeAll(cas, <String>['TGC=ticket-granting; Path=/; Secure'])
    ..storeAll(mdw, <String>['JSESSIONID=mdw-session; Path=/']);

  test('export keys cookies by the exact URLs the Go bridge expects', () {
    final decoded =
        jsonDecode(CasSession.export(signedInJar(), hosts))
            as Map<String, dynamic>;

    expect(decoded['version'], 1);
    final cookies = decoded['cookies'] as Map<String, dynamic>;
    expect(cookies.keys, unorderedEquals(hosts));
  });

  test('export uses Go http.Cookie field names', () {
    final decoded =
        jsonDecode(CasSession.export(signedInJar(), hosts))
            as Map<String, dynamic>;
    final casCookies =
        (decoded['cookies'] as Map<String, dynamic>)[hosts[0]] as List<dynamic>;

    expect(casCookies, isNotEmpty);
    for (final Object? entry in casCookies) {
      expect(entry, isA<Map<String, dynamic>>());
      expect((entry! as Map<String, dynamic>).keys, <String>['Name', 'Value']);
    }
  });

  test('each host only carries its own cookies', () {
    final decoded =
        jsonDecode(CasSession.export(signedInJar(), hosts))
            as Map<String, dynamic>;
    final cookies = decoded['cookies'] as Map<String, dynamic>;

    String valueOf(String host, String name) =>
        ((cookies[host] as List<dynamic>).firstWhere(
                  (Object? c) => (c! as Map<String, dynamic>)['Name'] == name,
                )
                as Map<String, dynamic>)['Value']
            as String;

    expect(valueOf(hosts[0], 'JSESSIONID'), 'cas-session');
    expect(valueOf(hosts[1], 'JSESSIONID'), 'mdw-session');
  });

  test('round-trips through import', () {
    final exported = CasSession.export(signedInJar(), hosts);

    final restored = CookieJar();
    CasSession.import(restored, exported);

    expect(restored.headerFor(cas), contains('JSESSIONID=cas-session'));
    expect(restored.headerFor(cas), contains('TGC=ticket-granting'));
    expect(restored.headerFor(mdw), contains('JSESSIONID=mdw-session'));
  });

  test('imports an envelope produced by the Go bridge', () {
    // Go marshals the full http.Cookie struct. The extra fields must not trip
    // the parse.
    const goExport =
        '{"version":1,"cookies":{'
        '"https://cas.insa-rennes.fr/cas/login":[{"Name":"TGC","Value":"abc",'
        '"Path":"","Domain":"","Expires":"0001-01-01T00:00:00Z",'
        '"MaxAge":0,"Secure":false,"HttpOnly":false,"SameSite":0,'
        '"Raw":"","Unparsed":null}],'
        '"https://mdw.insa-rennes.fr":[{"Name":"JSESSIONID","Value":"xyz"}]}}';

    final jar = CookieJar();
    CasSession.import(jar, goExport);

    expect(jar.headerFor(cas), 'TGC=abc');
    expect(jar.headerFor(mdw), 'JSESSIONID=xyz');
  });

  group('rejects a session it cannot trust', () {
    test('a future version', () {
      expect(
        () => CasSession.import(CookieJar(), '{"version":2,"cookies":{}}'),
        throwsFormatException,
      );
    });

    test('a missing cookie map', () {
      expect(
        () => CasSession.import(CookieJar(), '{"version":1}'),
        throwsFormatException,
      );
    });

    test('a non-object payload', () {
      expect(() => CasSession.import(CookieJar(), '[]'), throwsFormatException);
    });

    test('garbage', () {
      expect(
        () => CasSession.import(CookieJar(), 'not json'),
        throwsFormatException,
      );
    });
  });
}
