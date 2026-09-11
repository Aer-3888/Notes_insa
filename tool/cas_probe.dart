// Desktop parity check for the CAS client against the real CAS.
//
//   dart run tool/cas_probe.dart [--trace] [--save <file>] [--show-cookies]
//
// Walks the whole sign-in including 2FA, then checks the session opens MDW.
// Credentials are read from the terminal and never stored.
import 'dart:convert';
import 'dart:io';

import 'package:notes_insa/services/cas/cas_client.dart';
import 'package:notes_insa/services/cas/cas_endpoints.dart';

const String mdwHome = 'https://mdw.insa-rennes.fr/';

Future<void> main(List<String> args) async {
  final trace = args.contains('--trace');
  final showCookies = args.contains('--show-cookies');
  final saveIndex = args.indexOf('--save');
  final savePath = saveIndex >= 0 && saveIndex + 1 < args.length
      ? args[saveIndex + 1]
      : null;

  final client = CasClient(
    logger: trace ? (String m) => stderr.writeln('  [http] $m') : null,
  );

  try {
    await _run(client, savePath: savePath, showCookies: showCookies);
  } on CasException catch (e) {
    _fail('${e.failure.name}: ${e.message}');
  } finally {
    client.close();
  }
}

Future<void> _run(
  CasClient client, {
  required String? savePath,
  required bool showCookies,
}) async {
  final username = _prompt('Identifiant INSA');
  final password = _promptSecret('Mot de passe');

  _step('auth');
  await client.auth(username, password);

  if (client.isTokenNeeded) {
    _ok('the CAS asked for a second factor');
    await _solveSecondFactor(client);
  } else {
    _ok('no second factor required');
  }

  _step('isAuthenticated');
  final authenticated = await client.isAuthenticated();
  if (!authenticated) {
    _fail('the CAS does not consider this session signed in');
    return;
  }
  _ok('the CAS reports a signed-in session');

  _step('exportSession');
  final session = client.exportSession();
  _describeSession(session, showCookies: showCookies);

  _step('MDW reachability');
  await _checkMdw(client);

  if (savePath != null) {
    File(savePath).writeAsStringSync(session);
    _ok('session written to $savePath');
  }

  stdout.writeln('\nAll checks passed.');
}

Future<void> _solveSecondFactor(CasClient client) async {
  stdout.writeln('\n  1) receive a code by e-mail');
  stdout.writeln('  2) type a code from an authenticator');
  stdout.writeln('  3) use a stored TOTP secret');
  final choice = _prompt('Choice [1/2/3]');

  switch (choice.trim()) {
    case '1':
      _step('triggerEmail');
      await client.triggerEmail();
      _ok('e-mail requested');
      _step('validate');
      await client.validate(_prompt('Code received').trim());
    case '3':
      _step('autoValidate');
      await client.autoValidate(_promptSecret('TOTP secret (base32)').trim());
    default:
      _step('validate');
      await client.validate(_prompt('Code').trim());
  }

  _ok('second factor accepted');
}

/// A CAS session is only useful if MDW honours it.
Future<void> _checkMdw(CasClient client) async {
  final session = jsonDecode(client.exportSession()) as Map<String, dynamic>;
  final cookies =
      (session['cookies']
              as Map<String, dynamic>)[CasEndpoints.defaultSessionHosts[1]]
          as List<dynamic>;

  if (cookies.isEmpty) {
    _fail('no MDW cookie: the service redirect did not complete');
    return;
  }

  final header = cookies
      .cast<Map<String, dynamic>>()
      .map((Map<String, dynamic> c) => '${c['Name']}=${c['Value']}')
      .join('; ');

  final http = HttpClient();
  try {
    final request = await http.getUrl(Uri.parse(mdwHome));
    request.followRedirects = false;
    request.headers.set('cookie', header);
    final response = await request.close();
    await response.drain<void>();

    final location = response.headers.value('location') ?? '';
    final bouncedToCas = location.contains('cas.insa-rennes.fr');

    if (response.statusCode == 200) {
      _ok('MDW answered 200; the grade fetch can take over');
    } else if (bouncedToCas) {
      _fail('MDW bounced the session back to the CAS (${response.statusCode})');
    } else {
      _warn('MDW answered ${response.statusCode} -> $location');
    }
  } finally {
    http.close(force: true);
  }
}

void _describeSession(String session, {required bool showCookies}) {
  final decoded = jsonDecode(session) as Map<String, dynamic>;
  final cookies = decoded['cookies'] as Map<String, dynamic>;

  stdout.writeln('  version ${decoded['version']}, ${session.length} bytes');
  for (final entry in cookies.entries) {
    final list = (entry.value as List<dynamic>).cast<Map<String, dynamic>>();
    final names = list
        .map((Map<String, dynamic> c) {
          final name = c['Name'] as String;
          if (!showCookies) return name;
          return '$name=${c['Value']}';
        })
        .join(', ');
    stdout.writeln(
      '  ${entry.key}\n    ${list.length} cookie(s)'
      '${names.isEmpty ? '' : ': $names'}',
    );
  }
  if (!showCookies) {
    stdout.writeln('  (values hidden; pass --show-cookies to print them)');
  }
}

String _prompt(String label) {
  stdout.write('$label: ');
  return stdin.readLineSync(encoding: utf8) ?? '';
}

String _promptSecret(String label) {
  stdout.write('$label: ');
  final wasEchoing = stdin.hasTerminal && stdin.echoMode;
  if (wasEchoing) stdin.echoMode = false;
  try {
    return stdin.readLineSync(encoding: utf8) ?? '';
  } finally {
    if (wasEchoing) stdin.echoMode = true;
    stdout.writeln();
  }
}

void _step(String name) => stdout.writeln('\n> $name');
void _ok(String message) => stdout.writeln('  OK   $message');
void _warn(String message) => stdout.writeln('  WARN $message');
void _fail(String message) {
  stdout.writeln('  FAIL $message');
  exitCode = 1;
}
