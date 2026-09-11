import 'dart:io';

import 'cas_endpoints.dart';
import 'cas_session.dart';
import 'http_session.dart';
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
  }) : session = HttpSession(httpClient: httpClient, logger: logger);

  final CasEndpoints endpoints;

  /// Shared with the MDW session, which needs the same authenticated cookies.
  final HttpSession session;

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
      'ERR_Auth',
      () => session.postForm(endpoints.loginUri, <String, String>{
        'username': username,
        'password': password,
        'execution': _execution,
        '_eventId': 'submit',
        'geolocation': '',
        'deviceFingerprint': '',
      }),
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
      'ERR_TriggerEmail',
      () => session.send(
        endpoints.mailCodeUri(_username, _userHash),
        method: 'POST',
      ),
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
      'ERR_Validate',
      () => session.postForm(endpoints.loginUri, <String, String>{
        '_eventId_submit': 'Login',
        'execution': _execution,
        'token': token,
      }),
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
      'ERR_IsAuthenticated',
      () => session.get(endpoints.statusUri),
    );
    return response.body.contains('Log In Successful');
  }

  /// Serializes the session cookies. Never credentials or OTP secrets.
  String exportSession() =>
      CasSession.export(session.jar, endpoints.sessionHosts);

  /// Restores a session from [exportSession] or the native `ExportCAS`.
  void importSession(String serialized) {
    session.jar.clear();
    CasSession.import(session.jar, serialized);
    _tokenNeeded = false;
  }

  void close() => session.close();

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  Future<void> _fetchExecution() async {
    final response = await _send(
      'ERR_Auth',
      () => session.get(endpoints.loginUri),
    );
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

  /// Maps transport failures onto the CAS error vocabulary.
  static Future<HttpResult> _send(
    String errorCode,
    Future<HttpResult> Function() request,
  ) async {
    try {
      return await request();
    } on HttpSessionException catch (e) {
      throw CasException(errorCode, CasFailure.network, e.message);
    }
  }
}
