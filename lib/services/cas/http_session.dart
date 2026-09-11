import 'dart:convert';
import 'dart:io';

import 'cookie_jar.dart';

class HttpResult {
  const HttpResult(this.statusCode, this.body, this.finalUri);

  final int statusCode;
  final String body;

  /// Where the redirect chain ended.
  final Uri finalUri;
}

/// A cookie-carrying HTTP session that follows redirects by hand, so the jar
/// sees every hop. The CAS sign-in and the MDW session share one.
class HttpSession {
  HttpSession({HttpClient? httpClient, this.logger})
    : _http = httpClient ?? HttpClient() {
    _http.userAgent = userAgent;
  }

  /// The CAS serves a different login form to some mobile agents.
  static const String userAgent =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0 Safari/537.36';

  static const int _maxRedirects = 10;
  static const Duration timeout = Duration(seconds: 30);

  final HttpClient _http;
  final void Function(String message)? logger;
  final CookieJar jar = CookieJar();

  void close() => _http.close(force: true);

  Future<HttpResult> get(Uri uri) => send(uri);

  Future<HttpResult> postForm(Uri uri, Map<String, String> form) => send(
    uri,
    method: 'POST',
    body: _encodeForm(form),
    contentType: ContentType('application', 'x-www-form-urlencoded'),
  );

  Future<HttpResult> postJson(Uri uri, Object payload) => send(
    uri,
    method: 'POST',
    body: jsonEncode(payload),
    contentType: ContentType('application', 'json'),
  );

  /// Sends [body] with [contentType], following redirects and applying the jar
  /// at every hop. Throws [HttpSessionException] when the request cannot
  /// complete or redirects too many times.
  Future<HttpResult> send(
    Uri uri, {
    String method = 'GET',
    String? body,
    ContentType? contentType,
  }) async {
    var current = uri;
    var currentMethod = method;
    String? currentBody = body;

    for (var hop = 0; ; hop++) {
      if (hop > _maxRedirects) {
        throw HttpSessionException('too many redirects from ${uri.host}');
      }

      final int statusCode;
      final String responseBody;
      final String? location;
      try {
        final request = await _http
            .openUrl(currentMethod, current)
            .timeout(timeout);
        request.followRedirects = false;

        final cookies = jar.headerFor(current);
        if (cookies != null) request.headers.set('cookie', cookies);

        if (currentBody != null) {
          if (contentType != null) request.headers.contentType = contentType;
          request.write(currentBody);
        }

        final response = await request.close().timeout(timeout);
        responseBody = await response
            .transform(utf8.decoder)
            .join()
            .timeout(timeout);

        statusCode = response.statusCode;
        location = response.headers.value(HttpHeaders.locationHeader);
        jar.storeAll(
          current,
          response.headers[HttpHeaders.setCookieHeader] ?? const <String>[],
        );
      } on HttpSessionException {
        rethrow;
      } on Exception catch (e) {
        throw HttpSessionException('request to ${current.host} failed: $e');
      }

      if (!_isRedirect(statusCode) || location == null) {
        return HttpResult(statusCode, responseBody, current);
      }

      current = current.resolve(location);
      // 301/302/303 drop the body and switch to GET. 307/308 replay as-is.
      if (statusCode != HttpStatus.temporaryRedirect &&
          statusCode != HttpStatus.permanentRedirect) {
        currentMethod = 'GET';
        currentBody = null;
      }

      logger?.call('$statusCode -> ${current.host}${current.path}');
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

class HttpSessionException implements Exception {
  HttpSessionException(this.message);

  final String message;

  @override
  String toString() => 'HttpSessionException: $message';
}
