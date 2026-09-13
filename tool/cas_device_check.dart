// On-device checks for the CAS client, run as an alternate app entrypoint so
// nothing is added to the app's dependencies. Results appear on screen and on
// the console, prefixed CAS-CHECK.
//
//   flutter run -t tool/cas_device_check.dart -d <device-id> \
//     [--dart-define=CAS_USER=... --dart-define=CAS_PASS=...] \
//     [--dart-define=CAS_TOTP=<base32 secret>]
//
// Without CAS_USER it only runs the checks that need no account. Credentials
// are used once and never stored.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:notes_insa/services/cas/cas_client.dart';
import 'package:notes_insa/services/cas/cas_endpoints.dart';
import 'package:notes_insa/services/cas/cas_session.dart';
import 'package:notes_insa/services/cas/cookie_jar.dart';

const String casUser = String.fromEnvironment('CAS_USER');
const String casPass = String.fromEnvironment('CAS_PASS');
const String casTotp = String.fromEnvironment('CAS_TOTP');

enum Outcome { pass, fail, skip }

class CheckResult {
  CheckResult(this.name, this.outcome, this.detail);

  final String name;
  final Outcome outcome;
  final String detail;
}

void main() => runApp(const CasCheckApp());

class CasCheckApp extends StatelessWidget {
  const CasCheckApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'CAS device check',
    theme: ThemeData(colorSchemeSeed: const Color(0xFFE30613)),
    home: const CasCheckScreen(),
  );
}

class CasCheckScreen extends StatefulWidget {
  const CasCheckScreen({super.key});

  @override
  State<CasCheckScreen> createState() => _CasCheckScreenState();
}

class _CasCheckScreenState extends State<CasCheckScreen> {
  final List<CheckResult> _results = <CheckResult>[];
  bool _done = false;

  @override
  void initState() {
    super.initState();
    unawaited(_runAll());
  }

  void _record(String name, Outcome outcome, String detail) {
    debugPrint('CAS-CHECK ${outcome.name.toUpperCase()}  $name, $detail');
    if (!mounted) return;
    setState(() => _results.add(CheckResult(name, outcome, detail)));
  }

  Future<void> _runAll() async {
    debugPrint('CAS-CHECK ==== start ====');
    await _checkRefusal();
    await _checkNoSession();
    await _checkSignIn();
    debugPrint('CAS-CHECK ==== done ====');
    if (mounted) setState(() => _done = true);
  }

  /// Reaching badCredentials means the page parsed and the CAS accepted the
  /// scraped execution token. A rejected token gives unexpectedResponse.
  Future<void> _checkRefusal() async {
    const name = 'refuses a nonexistent account';
    final client = CasClient();
    try {
      await client.auth('zz-nonexistent-probe', 'not-a-real-password');
      _record(name, Outcome.fail, 'the CAS accepted a nonexistent account');
    } on CasException catch (e) {
      _record(
        name,
        e.failure == CasFailure.badCredentials ? Outcome.pass : Outcome.fail,
        'failure=${e.failure.name}',
      );
    } finally {
      client.close();
    }
  }

  Future<void> _checkNoSession() async {
    const name = 'reports no session before signing in';
    final client = CasClient();
    try {
      final authenticated = await client.isAuthenticated();
      _record(
        name,
        authenticated ? Outcome.fail : Outcome.pass,
        'isAuthenticated=$authenticated',
      );
    } on CasException catch (e) {
      _record(name, Outcome.fail, e.message);
    } finally {
      client.close();
    }
  }

  Future<void> _checkSignIn() async {
    const name = 'signs in and hands MDW a session it honours';
    if (casUser.isEmpty) {
      _record(name, Outcome.skip, 'pass --dart-define=CAS_USER / CAS_PASS');
      return;
    }

    final client = CasClient(
      logger: (String m) => debugPrint('CAS-CHECK   [http] $m'),
    );
    try {
      await client.auth(casUser, casPass);

      if (client.isTokenNeeded) {
        _record('detects the 2FA challenge', Outcome.pass, 'token required');
        if (casTotp.isEmpty) {
          _record(name, Outcome.skip, 'pass --dart-define=CAS_TOTP to finish');
          return;
        }
        await client.autoValidate(casTotp);
        _record('2FA accepted', Outcome.pass, 'autoValidate succeeded');
      }

      if (!await client.isAuthenticated()) {
        _record(name, Outcome.fail, 'the CAS refused the session it issued');
        return;
      }

      final jar = CookieJar();
      CasSession.import(jar, client.exportSession());
      final mdwCookies = jar.cookiesFor(
        Uri.parse(CasEndpoints.defaultSessionHosts[1]),
      );

      if (mdwCookies.isEmpty) {
        _record(name, Outcome.fail, 'no MDW cookie: service redirect failed');
        return;
      }

      final status = await _mdwStatus(mdwCookies);
      _record(
        name,
        status == 200 ? Outcome.pass : Outcome.fail,
        'MDW answered $status to ${mdwCookies.length} cookie(s)',
      );
    } on CasException catch (e) {
      _record(name, Outcome.fail, '${e.failure.name}: ${e.message}');
    } finally {
      client.close();
    }
  }

  Future<int> _mdwStatus(List<StoredCookie> cookies) async {
    final http = HttpClient();
    try {
      final request = await http.getUrl(
        Uri.parse('https://mdw.insa-rennes.fr/'),
      );
      request.followRedirects = false;
      request.headers.set(
        'cookie',
        cookies.map((StoredCookie c) => '${c.name}=${c.value}').join('; '),
      );
      final response = await request.close();
      await response.drain<void>();
      return response.statusCode;
    } finally {
      http.close(force: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final failed = _results.any((CheckResult r) => r.outcome == Outcome.fail);

    return Scaffold(
      appBar: AppBar(
        title: const Text('CAS device check'),
        backgroundColor: _done
            ? (failed ? Colors.red.shade700 : Colors.green.shade700)
            : null,
        foregroundColor: _done ? Colors.white : null,
      ),
      body: ListView(
        children: <Widget>[
          for (final CheckResult result in _results)
            ListTile(
              leading: Icon(
                switch (result.outcome) {
                  Outcome.pass => Icons.check_circle,
                  Outcome.fail => Icons.cancel,
                  Outcome.skip => Icons.remove_circle_outline,
                },
                color: switch (result.outcome) {
                  Outcome.pass => Colors.green,
                  Outcome.fail => Colors.red,
                  Outcome.skip => Colors.grey,
                },
              ),
              title: Text(result.name),
              subtitle: Text(result.detail),
            ),
          if (!_done)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
