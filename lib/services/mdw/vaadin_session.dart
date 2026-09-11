import 'dart:async';
import 'dart:convert';

import '../cas/http_session.dart';
import 'vaadin_types.dart';

/// A Vaadin Flow UIDL session against MDW.
///
/// Needs an [HttpSession] already authenticated through the CAS. Vaadin numbers
/// every exchange, so syncId and clientId are resynchronised after each send.
class VaadinSession {
  VaadinSession(this._http, {this.baseUrl = defaultBaseUrl, this.onResponse});

  static const String defaultBaseUrl = 'https://mdw.insa-rennes.fr';

  /// Vaadin prefixes UIDL responses with `for(;;);` to defeat JSON hijacking.
  static const String _jsonGuard = 'for(;;);';

  final HttpSession _http;
  final String baseUrl;

  /// Receives every decoded response, for the capture tool.
  final void Function(String label, Map<String, dynamic> body)? onResponse;

  int uiId = 0;
  int syncId = 0;
  int clientId = 0;
  String csrfToken = '';
  int beatIntervalSeconds = 0;

  Timer? _heartbeat;

  Uri get _uidlUri => Uri.parse('$baseUrl/?v-r=uidl&v-uiId=$uiId');

  /// Bootstraps the session and reads the ids every later request needs.
  Future<void> init() async {
    final result = await _http.get(
      Uri.parse('$baseUrl/?v-r=init&location=inscriptions&query='),
    );

    final Object? decoded;
    try {
      decoded = jsonDecode(result.body);
    } on FormatException {
      throw VaadinException(
        'init did not return JSON (HTTP ${result.statusCode}); the CAS '
        'session was probably not accepted',
      );
    }

    if (decoded is! Map<String, dynamic>) {
      throw VaadinException('init returned ${decoded.runtimeType}');
    }
    onResponse?.call('init', decoded);

    final appConfig = decoded['appConfig'];
    if (appConfig is! Map<String, dynamic>) {
      throw VaadinException('init response has no appConfig');
    }
    final uidl = appConfig['uidl'];
    if (uidl is! Map<String, dynamic>) {
      throw VaadinException('init response has no uidl');
    }

    uiId = (appConfig['v-uiId'] as num?)?.toInt() ?? 0;
    syncId = (uidl['syncId'] as num?)?.toInt() ?? 0;
    clientId = (uidl['clientId'] as num?)?.toInt() ?? 0;
    csrfToken = uidl['Vaadin-Security-Key'] as String? ?? '';
    beatIntervalSeconds =
        (appConfig['heartbeatInterval'] as num?)?.toInt() ?? 0;
  }

  /// Sends one UIDL request and returns its payload.
  Future<VaadinData> send(List<VaadinRpc> rpc, {String label = 'uidl'}) async {
    final payload = <String, dynamic>{
      'syncId': syncId,
      'clientId': clientId,
      'csrfToken': csrfToken,
      'rpc': rpc.map((VaadinRpc r) => r.toJson()).toList(),
    };

    final result = await _http.postJson(_uidlUri, payload);
    final body = _stripGuard(result.body);

    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw VaadinException(
        'UIDL response was not JSON (HTTP ${result.statusCode})',
      );
    }

    // Vaadin wraps the payload in a single-element array.
    final Map<String, dynamic> first;
    if (decoded is List && decoded.isNotEmpty) {
      final head = decoded.first;
      if (head is! Map<String, dynamic>) {
        throw VaadinException('unexpected UIDL element ${head.runtimeType}');
      }
      first = head;
    } else if (decoded is Map<String, dynamic>) {
      first = decoded;
    } else {
      throw VaadinException('unexpected UIDL shape ${decoded.runtimeType}');
    }

    final response = VaadinResponse.fromJson(first);
    if (response.sessionExpired) {
      throw VaadinException('session expired');
    }

    syncId = response.syncId;
    clientId = response.clientId;
    onResponse?.call(label, first);

    return response.data;
  }

  /// Tells the server the session is still alive.
  Future<void> beat() async {
    await _http.send(
      Uri.parse('$baseUrl/?v-r=heartbeat&v-uiId=$uiId'),
      method: 'POST',
    );
  }

  /// Beats in the background. Without it the session expires within about
  /// [beatIntervalSeconds], which is short enough to matter mid-fetch.
  void startBeating() {
    if (beatIntervalSeconds <= 0) return;
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(
      Duration(seconds: beatIntervalSeconds),
      (_) => unawaited(beat().catchError((Object _) {})),
    );
  }

  void stopBeating() {
    _heartbeat?.cancel();
    _heartbeat = null;
  }

  Future<void> unload() async {
    stopBeating();
    await _http.postJson(_uidlUri, <String, dynamic>{
      'syncId': syncId,
      'clientId': clientId,
      'csrfToken': csrfToken,
      'rpc': <dynamic>[],
      'UNLOAD': true,
    });
  }

  static String _stripGuard(String body) {
    final trimmed = body.trimLeft();
    return trimmed.startsWith(_jsonGuard)
        ? trimmed.substring(_jsonGuard.length)
        : trimmed;
  }
}
