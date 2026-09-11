import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/services/cas/cookie_jar.dart';

void main() {
  final cas = Uri.parse('https://cas.insa-rennes.fr/cas/login');
  final mdw = Uri.parse('https://mdw.insa-rennes.fr/');

  group('scoping', () {
    test('a cookie with no Domain is not sent to other hosts', () {
      final jar = CookieJar()
        ..storeAll(cas, <String>['JSESSIONID=abc; Path=/']);

      expect(jar.headerFor(cas), 'JSESSIONID=abc');
      expect(jar.headerFor(mdw), isNull);
    });

    test('a Domain cookie reaches subdomains', () {
      final jar = CookieJar()
        ..storeAll(cas, <String>['shared=1; Domain=insa-rennes.fr; Path=/']);

      expect(jar.headerFor(mdw), 'shared=1');
    });

    test('a cookie cannot scope itself to an unrelated domain', () {
      final jar = CookieJar()
        ..storeAll(cas, <String>['evil=1; Domain=example.com; Path=/']);

      expect(jar.isEmpty, isTrue);
    });

    test('Secure cookies are withheld from plain http', () {
      final jar = CookieJar()..storeAll(cas, <String>['TGC=t; Path=/; Secure']);

      expect(jar.headerFor(cas), 'TGC=t');
      expect(
        jar.headerFor(Uri.parse('http://cas.insa-rennes.fr/cas/login')),
        isNull,
      );
    });
  });

  group('path matching', () {
    test('honours an explicit Path prefix', () {
      final jar = CookieJar()..storeAll(cas, <String>['scoped=1; Path=/cas']);

      expect(
        jar.headerFor(Uri.parse('https://cas.insa-rennes.fr/cas/login')),
        'scoped=1',
      );
      expect(
        jar.headerFor(Uri.parse('https://cas.insa-rennes.fr/other')),
        isNull,
      );
    });

    test('a bare prefix that is not a path segment does not match', () {
      final jar = CookieJar()..storeAll(cas, <String>['scoped=1; Path=/cas']);

      expect(
        jar.headerFor(Uri.parse('https://cas.insa-rennes.fr/castle')),
        isNull,
      );
    });

    test('defaults the path to the directory of the request', () {
      final jar = CookieJar()..storeAll(cas, <String>['d=1']);

      expect(
        jar.headerFor(Uri.parse('https://cas.insa-rennes.fr/cas/x')),
        'd=1',
      );
      expect(jar.headerFor(Uri.parse('https://cas.insa-rennes.fr/')), isNull);
    });

    test('sends the most specific path first', () {
      final jar = CookieJar()
        ..storeAll(cas, <String>['a=1; Path=/'])
        ..storeAll(cas, <String>['b=2; Path=/cas/login']);

      expect(jar.headerFor(cas), 'b=2; a=1');
    });
  });

  group('lifetime', () {
    test('Max-Age=0 deletes the cookie', () {
      final jar = CookieJar()
        ..storeAll(cas, <String>['JSESSIONID=abc; Path=/'])
        ..storeAll(cas, <String>['JSESSIONID=abc; Path=/; Max-Age=0']);

      expect(jar.headerFor(cas), isNull);
    });

    test('an expired Expires is dropped', () {
      final jar = CookieJar()
        ..storeAll(cas, <String>[
          'old=1; Path=/; Expires=Thu, 01 Jan 2015 00:00:00 GMT',
        ]);

      expect(jar.headerFor(cas), isNull);
    });

    test('a future Expires is kept', () {
      final jar = CookieJar()
        ..storeAll(cas, <String>[
          'new=1; Path=/; Expires=Fri, 01 Jan 2100 00:00:00 GMT',
        ]);

      expect(jar.headerFor(cas), 'new=1');
    });

    test('Max-Age wins over Expires', () {
      final jar = CookieJar()
        ..storeAll(cas, <String>[
          'x=1; Path=/; Expires=Thu, 01 Jan 2015 00:00:00 GMT; Max-Age=600',
        ]);

      expect(jar.headerFor(cas), 'x=1');
    });

    test('a later Set-Cookie replaces the same name/path', () {
      final jar = CookieJar()
        ..storeAll(cas, <String>['JSESSIONID=one; Path=/'])
        ..storeAll(cas, <String>['JSESSIONID=two; Path=/']);

      expect(jar.headerFor(cas), 'JSESSIONID=two');
    });
  });

  group('parsing', () {
    test('keeps base64-ish values intact', () {
      const value = 'eyJhbGciOi.J9-_=';
      final jar = CookieJar()
        ..storeAll(cas, <String>['TGC=$value; Path=/; HttpOnly; Secure']);

      expect(jar.headerFor(cas), 'TGC=$value');
    });

    test('ignores a header with no name', () {
      final jar = CookieJar()..storeAll(cas, <String>['=orphan; Path=/']);

      expect(jar.isEmpty, isTrue);
    });

    test('stores several cookies from one response', () {
      final jar = CookieJar()
        ..storeAll(cas, <String>[
          'JSESSIONID=a; Path=/',
          'TGC=b; Path=/; Secure',
        ]);

      expect(jar.headerFor(cas), contains('JSESSIONID=a'));
      expect(jar.headerFor(cas), contains('TGC=b'));
    });
  });

  group('real CAS response', () {
    // Captured from cas.insa-rennes.fr. The sticky-session cookie spells its
    // attribute `path` in lowercase, and dropping it breaks the login.
    const setCookies = <String>[
      'XSRF-TOKEN=3cdc7aed-0a19-4e5e-bd41-8200e61b7881; Path=/cas; Secure; '
          'HttpOnly',
      'org.springframework.web.servlet.i18n.CookieLocaleResolver.LOCALE=en; '
          'Path=/; Secure; HttpOnly; SameSite=Lax',
      'SERVID=cas-vmp-app01; path=/',
    ];

    test('keeps every cookie the CAS sets', () {
      final jar = CookieJar()..storeAll(cas, setCookies);
      final header = jar.headerFor(cas)!;

      expect(
        header,
        contains('XSRF-TOKEN=3cdc7aed-0a19-4e5e-bd41-8200e61b7881'),
      );
      expect(header, contains('SERVID=cas-vmp-app01'));
      expect(header, contains('CookieLocaleResolver.LOCALE=en'));
    });

    test('scopes the XSRF token to /cas', () {
      final jar = CookieJar()..storeAll(cas, setCookies);

      expect(jar.headerFor(cas), contains('XSRF-TOKEN='));
      expect(
        jar.headerFor(Uri.parse('https://cas.insa-rennes.fr/other')),
        isNot(contains('XSRF-TOKEN=')),
      );
    });

    test('none of them leak to MDW', () {
      final jar = CookieJar()..storeAll(cas, setCookies);

      expect(jar.headerFor(mdw), isNull);
    });
  });
}
