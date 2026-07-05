import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Small HTTP wrapper adding a per-attempt timeout, retry with exponential
/// backoff for transient failures (HTTP 429 / 5xx and connection/timeout
/// errors), and Retry-After support. Also provides a defensive JSON decode so an
/// HTML error page never throws deep inside a parser.
///
/// The community endpoints (averages, coefficients) are effectively idempotent
/// upserts, so retrying both GET and POST is safe here.
class ResilientHttp {
  static const int _defaultRetries = 2;
  static const Duration _baseBackoff = Duration(milliseconds: 400);
  static const Duration _maxRetryAfter = Duration(seconds: 60);

  static bool _isTransientStatus(int status) => status == 429 || status >= 500;

  /// GET with retry/backoff. Returns the final response, or null when every
  /// attempt hit a connection/timeout error.
  static Future<http.Response?> get(
    Uri uri, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 15),
    int retries = _defaultRetries,
  }) => _send(() => http.get(uri, headers: headers), timeout, retries);

  /// POST with retry/backoff (see class note on idempotency).
  static Future<http.Response?> post(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Duration timeout = const Duration(seconds: 10),
    int retries = _defaultRetries,
  }) => _send(
    () => http.post(uri, headers: headers, body: body),
    timeout,
    retries,
  );

  static Future<http.Response?> _send(
    Future<http.Response> Function() attempt,
    Duration timeout,
    int retries,
  ) async {
    for (var i = 0; ; i++) {
      try {
        final response = await attempt().timeout(timeout);
        if (!_isTransientStatus(response.statusCode) || i >= retries) {
          return response;
        }
        await Future<void>.delayed(_backoff(i, response));
      } on TimeoutException {
        if (i >= retries) return null;
        await Future<void>.delayed(_backoff(i, null));
      } on SocketException {
        if (i >= retries) return null;
        await Future<void>.delayed(_backoff(i, null));
      } on http.ClientException {
        if (i >= retries) return null;
        await Future<void>.delayed(_backoff(i, null));
      }
    }
  }

  static Duration _backoff(int attempt, http.Response? response) {
    // Honor Retry-After in either allowed form: delta-seconds or an HTTP-date.
    final retryAfter = response?.headers['retry-after'];
    if (retryAfter != null) {
      final trimmed = retryAfter.trim();
      final secs = int.tryParse(trimmed);
      if (secs != null && secs >= 0)
        return _capRetryAfter(Duration(seconds: secs));
      try {
        final delay = HttpDate.parse(
          trimmed,
        ).difference(DateTime.now().toUtc());
        if (!delay.isNegative) return _capRetryAfter(delay);
      } catch (_) {
        // Not an HTTP-date either; fall through to exponential backoff.
      }
    }
    // Exponential backoff: base, 2x, 4x, ...
    return _baseBackoff * (1 << attempt);
  }

  static Duration _capRetryAfter(Duration d) =>
      d <= _maxRetryAfter ? d : _maxRetryAfter;

  /// Decodes [response] as JSON only when it is a 200 that actually looks like
  /// JSON (by content-type or a leading brace/bracket). Returns null otherwise,
  /// so a redirect/HTML error body is rejected instead of throwing.
  static dynamic decodeJson(http.Response? response) {
    if (response == null || response.statusCode != 200) return null;
    final contentType = response.headers['content-type'] ?? '';
    final body = response.body.trimLeft();
    final looksJson =
        contentType.contains('json') ||
        body.startsWith('{') ||
        body.startsWith('[');
    if (!looksJson) return null;
    try {
      return jsonDecode(response.body);
    } catch (e) {
      if (kDebugMode) debugPrint('[ResilientHttp] JSON decode failed: $e');
      return null;
    }
  }
}
