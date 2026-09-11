import 'dart:convert';
import 'dart:io';

import 'cas_endpoints.dart';
import 'cas_session.dart';
import 'cookie_jar.dart';
import 'totp.dart';

/// Why a CAS call failed, for the cases the UI treats differently.
enum CasFailure {
  /// Username or password rejected.
  badCredentials,

  /// The submitted 2FA code was refused; a new one can be entered.
  badToken,

  /// A code was submitted when none was pending, or vice versa.
  tokenStateMismatch,

  /// The CAS answered, but not with anything the flow recognises.
  unexpectedResponse,

  /// The request never completed.
  network,
}

class CasException implements Exception {
  CasException(this.code, this.failure, this.message);

  /// Mirrors the native bridge's `ERR_<Method>` codes.
  final String code;
  final CasFailure failure;
  final String message;

  @override
  String toString() => 'CasException($code): $message';
}

/// The INSA Rennes CAS sign-in, with its mail and TOTP second factors.
///
/// Exports its session in the envelope the native MDW bridge reads, so the
/// grade fetch keeps working unchanged (see [CasSession]).
class CasClient {
  CasClient({
    this.endpoints = CasEndpoints.insa,
    HttpClient? httpClient,
    void Function(String message)? logger,
  }) : _http = httpClient ?? HttpClient(),
       _log = logger {
    _http.userAgent = _userAgent;
  }

  final CasEndpoints endpoints;

  /// Traces the redirect chain. Null in the app, set by the probe tools.
  final void Function(String message)? _log;

  /// The CAS serves a different login form to some mobile agents.
  static const String _userAgent =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0 Safari/537.36';

  static const int _maxRedirects = 10;
  static const Duration _timeout = Duration(seconds: 30);

  final HttpClient _http;
  final CookieJar _jar = CookieJar();

  String _username = '';
  String _userHash = '';
  String _execution = '';
  bool _tokenNeeded = false;

  /// True when the CAS answered the credential step with an MFA challenge.
  bool get isTokenNeeded => _tokenNeeded;

  /// Submits username and password. When [isTokenNeeded] is set on return,
  /// the sign-in needs [validate] or [autoValidate] to finish.
  Future<void> auth(String username, String password) async {
    _tokenNeeded = false;
    _username = username;

    await _fetchExecution();

    final response = await _send(
      endpoints.loginUri,
      method: 'POST',
      form: <String, String>{
        'username': username,
        'password': password,
        'execution': _execution,
        '_eventId': 'submit',
        'geolocation': '',
        'deviceFingerprint': '',
      },
      errorCode: 'ERR_Auth',
    );

    if (response.statusCode == HttpStatus.unauthorized) {
      throw CasException(
        'ERR_Auth',
        CasFailure.badCredentials,
        'Identifiant ou mot de passe incorrect.',
      );
    }

    if (response.body.contains('Multi-Factor Authentication')) {
      _execution = _extractExecution(response.body, 'ERR_Auth');
      _userHash = _extractUserHash(response.body);
      _tokenNeeded = true;
      return;
    }

    // A stale flow execution key comes back 500, not 401, and must not read
    // as a successful sign-in.
    if (response.statusCode >= 400) {
      throw CasException(
        'ERR_Auth',
        CasFailure.unexpectedResponse,
        'Réponse inattendue du CAS (HTTP ${response.statusCode}).',
      );
    }
  }

  /// Asks the OTP service to mail a one-time code to the signed-in user.
  Future<void> triggerEmail() async {
    if (_userHash.isEmpty) {
      throw CasException(
        'ERR_TriggerEmail',
        CasFailure.unexpectedResponse,
        'Aucun identifiant de session pour l’envoi du code.',
      );
    }

    final response = await _send(
      endpoints.mailCodeUri(_username, _userHash),
      method: 'POST',
      errorCode: 'ERR_TriggerEmail',
    );

    if (response.statusCode != HttpStatus.ok) {
      throw CasException(
        'ERR_TriggerEmail',
        CasFailure.unexpectedResponse,
        'Envoi du code par e-mail refusé (HTTP ${response.statusCode}).',
      );
    }
  }

  /// Submits a 2FA code, typed or from an authenticator.
  Future<void> validate(String token) async {
    if (!_tokenNeeded) {
      throw CasException(
        'ERR_Validate',
        CasFailure.tokenStateMismatch,
        'Aucun code de validation n’est attendu.',
      );
    }
    if (token.isEmpty) {
      throw CasException(
        'ERR_Validate',
        CasFailure.badToken,
        'Code de validation vide.',
      );
    }

    final response = await _send(
      endpoints.loginUri,
      method: 'POST',
      form: <String, String>{
        '_eventId_submit': 'Login',
        'execution': _execution,
        'token': token,
      },
      errorCode: 'ERR_Validate',
    );

    // An accepted code redirects out to the service.
    if (response.finalUri.host == endpoints.casHost &&
        response.statusCode != HttpStatus.ok) {
      _execution = _extractExecution(response.body, 'ERR_Validate');
      throw CasException(
        'ERR_Validate',
        CasFailure.badToken,
        'Code de validation incorrect.',
      );
    }

    _tokenNeeded = false;
  }

  /// Derives a TOTP code from [secret] and submits it.
  Future<void> autoValidate(String secret) async {
    final String code;
    try {
      code = Totp.generate(secret);
    } on FormatException catch (e) {
      throw CasException(
        'ERR_AutoValidate',
        CasFailure.badToken,
        'Secret TOTP invalide: ${e.message}',
      );
    }
    await validate(code);
  }

  /// Asks the CAS whether the current cookies still represent a signed-in user.
  Future<bool> isAuthenticated() async {
    final response = await _send(
      endpoints.statusUri,
      errorCode: 'ERR_IsAuthenticated',
    );
    return response.body.contains('Log In Successful');
  }

  /// Serializes the session cookies. Never credentials or OTP secrets.
  String exportSession() => CasSession.export(_jar, endpoints.sessionHosts);

  /// Restores a session from [exportSession] or the native `ExportCAS`.
  void importSession(String serialized) {
    _jar.clear();
    CasSession.import(_jar, serialized);
    _tokenNeeded = false;
  }

  void close() => _http.close(force: true);

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  Future<void> _fetchExecution() async {
    final response = await _send(endpoints.loginUri, errorCode: 'ERR_Auth');
    if (response.statusCode != HttpStatus.ok) {
      throw CasException(
        'ERR_Auth',
        CasFailure.unexpectedResponse,
        'Le CAS n’a pas renvoyé de formulaire de connexion '
            '(HTTP ${response.statusCode}).',
      );
    }
    _execution = _extractExecution(response.body, 'ERR_Auth');
  }

  /// The CAS carries its CSRF token as a hidden `execution` input.
  static String _extractExecution(String body, String errorCode) {
    final input = RegExp(
      r'''<input[^>]*\bname=["']execution["'][^>]*>''',
      caseSensitive: false,
    ).firstMatch(body);

    if (input != null) {
      final value = RegExp(
        r'''\bvalue=["']([^"']*)["']''',
        caseSensitive: false,
      ).firstMatch(input.group(0)!);
      if (value != null) return value.group(1)!;
    }

    throw CasException(
      errorCode,
      CasFailure.unexpectedResponse,
      'Jeton de session introuvable dans la réponse du CAS.',
    );
  }

  /// The MFA page inlines the user hash the OTP service needs.
  static String _extractUserHash(String body) {
    final match = RegExp(
      r'''const\s+userHash\s*=\s*["']([^"']*)["']''',
    ).firstMatch(body);
    return match?.group(1) ?? '';
  }

  Future<_CasResponse> _send(
    Uri uri, {
    String method = 'GET',
    Map<String, String>? form,
    required String errorCode,
  }) async {
    var current = uri;
    var currentMethod = method;
    Map<String, String>? currentForm = form;

    for (var hop = 0; ; hop++) {
      if (hop > _maxRedirects) {
        throw CasException(
          errorCode,
          CasFailure.unexpectedResponse,
          'Trop de redirections depuis ${uri.host}.',
        );
      }

      final int statusCode;
      final String body;
      final String? location;
      try {
        final request = await _http
            .openUrl(currentMethod, current)
            .timeout(_timeout);
        request.followRedirects = false;

        final cookies = _jar.headerFor(current);
        if (cookies != null) request.headers.set('cookie', cookies);

        if (currentForm != null) {
          request.headers.contentType = ContentType(
            'application',
            'x-www-form-urlencoded',
          );
          request.write(_encodeForm(currentForm));
        }

        final response = await request.close().timeout(_timeout);
        body = await response.transform(utf8.decoder).join().timeout(_timeout);

        statusCode = response.statusCode;
        location = response.headers.value(HttpHeaders.locationHeader);
        _jar.storeAll(
          current,
          response.headers[HttpHeaders.setCookieHeader] ?? const <String>[],
        );
      } on CasException {
        rethrow;
      } on Exception catch (e) {
        throw CasException(
          errorCode,
          CasFailure.network,
          'Connexion au service impossible: $e',
        );
      }

      if (!_isRedirect(statusCode) || location == null) {
        return _CasResponse(statusCode, body, current);
      }

      current = current.resolve(location);
      // 301/302/303 drop the body and switch to GET. 307/308 replay as-is.
      if (statusCode != HttpStatus.temporaryRedirect &&
          statusCode != HttpStatus.permanentRedirect) {
        currentMethod = 'GET';
        currentForm = null;
      }

      _log?.call('$statusCode -> ${current.host}${current.path}');
    }
  }

  static String _encodeForm(Map<String, String> form) => form.entries
      .map(
        (MapEntry<String, String> e) =>
            '${Uri.encodeQueryComponent(e.key)}='
            '${Uri.encodeQueryComponent(e.value)}',
      )
      .join('&');

  static bool _isRedirect(int status) =>
      status == HttpStatus.movedPermanently ||
      status == HttpStatus.found ||
      status == HttpStatus.seeOther ||
      status == HttpStatus.temporaryRedirect ||
      status == HttpStatus.permanentRedirect;
}

class _CasResponse {
  const _CasResponse(this.statusCode, this.body, this.finalUri);

  final int statusCode;
  final String body;

  /// Where the redirect chain ended, which is how a refused 2FA code is told
  /// apart from an accepted one.
  final Uri finalUri;
}
