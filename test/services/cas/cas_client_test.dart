import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/services/cas/cas_client.dart';
import 'package:notes_insa/services/cas/cas_endpoints.dart';

/// Stand-in for the CAS, the OTP service and the MDW service endpoint. The CAS
/// is addressed as 127.0.0.1 and the service as localhost so they have distinct
/// hostnames, which is what [CasClient.validate] keys on.
class _FakeCas {
  _FakeCas(this._server);

  static const String goodUser = 'etudiant';
  static const String goodPassword = 'motdepasse';
  static const String mfaUser = 'etudiant2fa';
  static const String goodToken = '123456';
  static const String userHash = 'HASH-abc123';

  final HttpServer _server;
  bool _stopped = false;

  bool authenticated = false;

  /// Hands out an execution token the flow no longer knows.
  bool staleExecution = false;
  final List<String> mailedCodePaths = <String>[];
  final List<Map<String, String>> receivedForms = <Map<String, String>>[];

  int get port => _server.port;

  CasEndpoints get endpoints => CasEndpoints(
    casBaseUrl: 'http://127.0.0.1:$port/cas/login',
    otpBaseUrl: 'http://127.0.0.1:$port',
    service: 'http://localhost:$port/login/cas',
    sessionHosts: <String>[
      'http://127.0.0.1:$port/cas/login',
      'http://localhost:$port',
    ],
  );

  static Future<_FakeCas> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = _FakeCas(server);
    unawaited(fake._serve());
    return fake;
  }

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    await _server.close(force: true);
  }

  Future<void> _serve() async {
    await for (final HttpRequest request in _server) {
      final body = await utf8.decoder.bind(request).join();
      try {
        await _route(request, body);
      } finally {
        await request.response.close();
      }
    }
  }

  Future<void> _route(HttpRequest request, String body) async {
    final path = request.uri.path;
    final response = request.response;

    if (path.startsWith('/users/')) {
      mailedCodePaths.add(path);
      response.statusCode = HttpStatus.ok;
      return;
    }

    if (path == '/login/cas') {
      // This round trip is what establishes the MDW session cookie.
      response.headers.add('set-cookie', 'MDWSESSION=mdw-1; Path=/');
      response.write('service ok');
      return;
    }

    if (path != '/cas/login') {
      response.statusCode = HttpStatus.notFound;
      return;
    }

    if (request.method == 'GET') {
      response.headers.add('set-cookie', 'JSESSIONID=cas-1; Path=/');
      response.write(
        authenticated
            ? _successPage
            : _loginForm(staleExecution ? 'exec-stale' : 'exec-initial'),
      );
      return;
    }

    final form = _parseForm(body);
    receivedForms.add(form);

    if (!_validExecutions.contains(form['execution'])) {
      // The real CAS answers an unknown flow key with a 500, not a 401.
      response.statusCode = HttpStatus.internalServerError;
      response.write(_badFlowKey);
      return;
    }

    if (form.containsKey('token')) {
      if (form['token'] == goodToken) {
        authenticated = true;
        _redirectToService(response);
      } else {
        response.statusCode = HttpStatus.unauthorized;
        response.write(_mfaPage('exec-retry'));
      }
      return;
    }

    if (form['password'] != goodPassword) {
      response.statusCode = HttpStatus.unauthorized;
      response.write('bad credentials');
      return;
    }

    if (form['username'] == mfaUser) {
      response.write(_mfaPage('exec-mfa'));
      return;
    }

    authenticated = true;
    _redirectToService(response);
  }

  void _redirectToService(HttpResponse response) {
    response.statusCode = HttpStatus.found;
    response.headers.add(
      'location',
      'http://localhost:$port/login/cas?ticket=ST-1',
    );
  }

  static Map<String, String> _parseForm(String body) {
    final form = <String, String>{};
    if (body.isEmpty) return form;
    for (final pair in body.split('&')) {
      final eq = pair.indexOf('=');
      if (eq < 0) continue;
      form[Uri.decodeQueryComponent(pair.substring(0, eq))] =
          Uri.decodeQueryComponent(pair.substring(eq + 1));
    }
    return form;
  }

  static String _loginForm(String execution) =>
      '<html><body><form method="post">'
      '<input type="hidden" name="execution" value="$execution" />'
      '<input type="submit" name="_eventId" value="submit" />'
      '</form></body></html>';

  static String _mfaPage(String execution) =>
      '<html><body><h1>Multi-Factor Authentication</h1>'
      '<form method="post">'
      '<input type="hidden" name="execution" value="$execution" />'
      '</form>'
      '<script>const userHash = "$userHash";</script>'
      '</body></html>';

  static const Set<String> _validExecutions = <String>{
    'exec-initial',
    'exec-mfa',
    'exec-retry',
  };

  static const String _badFlowKey =
      '{"status":500,"error":"Internal Server Error","message":'
      '"jakarta.servlet.ServletException: ...'
      'BadlyFormattedFlowExecutionKeyException: Badly formatted flow '
      'execution key","path":"/cas/login"}';

  static const String _successPage =
      '<html><body><h2>Log In Successful</h2></body></html>';
}

void main() {
  late _FakeCas fake;
  late CasClient client;

  setUpAll(() {
    // flutter_test installs an HttpClient that refuses every request.
    HttpOverrides.global = null;
  });

  setUp(() async {
    fake = await _FakeCas.start();
    client = CasClient(endpoints: fake.endpoints);
  });

  tearDown(() async {
    client.close();
    await fake.stop();
  });

  group('sign-in without a second factor', () {
    test('completes and reports no token needed', () async {
      await client.auth(_FakeCas.goodUser, _FakeCas.goodPassword);

      expect(client.isTokenNeeded, isFalse);
      expect(fake.authenticated, isTrue);
    });

    test('sends the execution token the form carried', () async {
      await client.auth(_FakeCas.goodUser, _FakeCas.goodPassword);

      expect(fake.receivedForms.single['execution'], 'exec-initial');
      expect(fake.receivedForms.single['_eventId'], 'submit');
    });

    test(
      'follows the service redirect and keeps both session cookies',
      () async {
        await client.auth(_FakeCas.goodUser, _FakeCas.goodPassword);

        final session =
            jsonDecode(client.exportSession()) as Map<String, dynamic>;
        final cookies = session['cookies'] as Map<String, dynamic>;

        expect(
          jsonEncode(cookies[fake.endpoints.sessionHosts[0]]),
          contains('cas-1'),
        );
        expect(
          jsonEncode(cookies[fake.endpoints.sessionHosts[1]]),
          contains('mdw-1'),
        );
      },
    );

    test(
      'does not mistake a stale flow key for a successful sign-in',
      () async {
        fake.staleExecution = true;

        await expectLater(
          client.auth(_FakeCas.goodUser, _FakeCas.goodPassword),
          throwsA(
            isA<CasException>().having(
              (CasException e) => e.failure,
              'failure',
              CasFailure.unexpectedResponse,
            ),
          ),
        );
        expect(fake.authenticated, isFalse);
      },
    );

    test('rejects a wrong password', () async {
      await expectLater(
        client.auth(_FakeCas.goodUser, 'wrong'),
        throwsA(
          isA<CasException>()
              .having(
                (CasException e) => e.failure,
                'failure',
                CasFailure.badCredentials,
              )
              .having((CasException e) => e.code, 'code', 'ERR_Auth'),
        ),
      );
    });
  });

  group('sign-in with a second factor', () {
    setUp(() async {
      await client.auth(_FakeCas.mfaUser, _FakeCas.goodPassword);
    });

    test('reports that a token is needed', () {
      expect(client.isTokenNeeded, isTrue);
      expect(fake.authenticated, isFalse);
    });

    test('mails a code to the user hash scraped from the MFA page', () async {
      await client.triggerEmail();

      expect(
        fake.mailedCodePaths.single,
        '/users/${_FakeCas.mfaUser}/methods/random_code_mail/transports/mail/'
        '${_FakeCas.userHash}',
      );
    });

    test('accepts the right code', () async {
      await client.validate(_FakeCas.goodToken);

      expect(client.isTokenNeeded, isFalse);
      expect(fake.authenticated, isTrue);
    });

    test('carries the MFA execution token, not the initial one', () async {
      await client.validate(_FakeCas.goodToken);

      expect(fake.receivedForms.last['execution'], 'exec-mfa');
      expect(fake.receivedForms.last['_eventId_submit'], 'Login');
    });

    test('rejects a wrong code and stays ready for another try', () async {
      await expectLater(
        client.validate('000000'),
        throwsA(
          isA<CasException>().having(
            (CasException e) => e.failure,
            'failure',
            CasFailure.badToken,
          ),
        ),
      );

      expect(client.isTokenNeeded, isTrue);

      // The refused attempt returned a fresh execution token.
      await client.validate(_FakeCas.goodToken);
      expect(fake.receivedForms.last['execution'], 'exec-retry');
      expect(fake.authenticated, isTrue);
    });

    test('rejects an empty code without contacting the server', () async {
      final before = fake.receivedForms.length;

      await expectLater(client.validate(''), throwsA(isA<CasException>()));
      expect(fake.receivedForms.length, before);
    });
  });

  group('session state', () {
    test('isAuthenticated tracks the CAS answer', () async {
      expect(await client.isAuthenticated(), isFalse);

      await client.auth(_FakeCas.goodUser, _FakeCas.goodPassword);
      expect(await client.isAuthenticated(), isTrue);
    });

    test('a restored session is sent back on the next request', () async {
      await client.auth(_FakeCas.goodUser, _FakeCas.goodPassword);
      final exported = client.exportSession();

      final restored = CasClient(endpoints: fake.endpoints)
        ..importSession(exported);
      addTearDown(restored.close);

      expect(await restored.isAuthenticated(), isTrue);
      expect(jsonDecode(restored.exportSession()), jsonDecode(exported));
    });

    test('validate refuses when no challenge is pending', () async {
      await expectLater(
        client.validate('123456'),
        throwsA(
          isA<CasException>().having(
            (CasException e) => e.failure,
            'failure',
            CasFailure.tokenStateMismatch,
          ),
        ),
      );
    });

    test('triggerEmail refuses without a user hash', () async {
      await expectLater(client.triggerEmail(), throwsA(isA<CasException>()));
    });
  });

  test('a dead server surfaces as a network failure', () async {
    await fake.stop();

    await expectLater(
      client.auth(_FakeCas.goodUser, _FakeCas.goodPassword),
      throwsA(
        isA<CasException>().having(
          (CasException e) => e.failure,
          'failure',
          CasFailure.network,
        ),
      ),
    );
  });
}
