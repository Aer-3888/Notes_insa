/// One stored cookie, reduced to the fields the CAS flow needs.
class StoredCookie {
  StoredCookie({
    required this.name,
    required this.value,
    required this.domain,
    required this.path,
    required this.hostOnly,
    this.secure = false,
    this.expires,
  });

  final String name;
  final String value;
  final String domain;
  final String path;

  /// Set when the Set-Cookie carried no Domain, so it never reaches subdomains.
  final bool hostOnly;
  final bool secure;
  final DateTime? expires;

  bool get isExpired {
    final at = expires;
    return at != null && at.isBefore(DateTime.now().toUtc());
  }
}

/// Minimal RFC 6265 cookie jar for the CAS sign-in.
class CookieJar {
  final List<StoredCookie> _cookies = <StoredCookie>[];

  /// Cookies to send to [uri], longest path first as the RFC requires.
  List<StoredCookie> cookiesFor(Uri uri) {
    _cookies.removeWhere((StoredCookie c) => c.isExpired);
    final host = uri.host.toLowerCase();
    final path = uri.path.isEmpty ? '/' : uri.path;
    final isSecure = uri.scheme == 'https';

    final matches = _cookies.where((StoredCookie c) {
      if (c.secure && !isSecure) return false;
      if (!_domainMatches(host, c)) return false;
      return _pathMatches(path, c.path);
    }).toList();

    matches.sort((StoredCookie a, StoredCookie b) {
      final byPath = b.path.length.compareTo(a.path.length);
      return byPath;
    });
    return matches;
  }

  /// [cookiesFor] as a `Cookie:` header value, or null when empty.
  String? headerFor(Uri uri) {
    final matches = cookiesFor(uri);
    if (matches.isEmpty) return null;
    return matches.map((StoredCookie c) => '${c.name}=${c.value}').join('; ');
  }

  void storeAll(Uri uri, List<String> setCookieHeaders) {
    for (final header in setCookieHeaders) {
      final cookie = _parse(uri, header);
      if (cookie != null) store(cookie);
    }
  }

  /// Stores one cookie, replacing any existing cookie with the same identity.
  void store(StoredCookie cookie) {
    _cookies.removeWhere(
      (StoredCookie c) =>
          c.name == cookie.name &&
          c.domain == cookie.domain &&
          c.path == cookie.path,
    );
    if (cookie.value.isEmpty || cookie.isExpired) return;
    _cookies.add(cookie);
  }

  /// Adds a bare name/value pair scoped to [uri]'s host, for restoring a
  /// session export that carries nothing else.
  void storeNameValue(Uri uri, String name, String value) {
    store(
      StoredCookie(
        name: name,
        value: value,
        domain: uri.host.toLowerCase(),
        path: '/',
        hostOnly: true,
      ),
    );
  }

  void clear() => _cookies.clear();

  bool get isEmpty => _cookies.isEmpty;

  static bool _domainMatches(String host, StoredCookie cookie) {
    if (host == cookie.domain) return true;
    if (cookie.hostOnly) return false;
    return host.endsWith('.${cookie.domain}');
  }

  static bool _pathMatches(String requestPath, String cookiePath) {
    if (requestPath == cookiePath) return true;
    if (!requestPath.startsWith(cookiePath)) return false;
    if (cookiePath.endsWith('/')) return true;
    return requestPath[cookiePath.length] == '/';
  }

  /// RFC 6265 default-path: the request path up to but excluding the last '/'.
  static String _defaultPath(Uri uri) {
    final path = uri.path;
    if (path.isEmpty || !path.startsWith('/')) return '/';
    final lastSlash = path.lastIndexOf('/');
    if (lastSlash <= 0) return '/';
    return path.substring(0, lastSlash);
  }

  static StoredCookie? _parse(Uri uri, String header) {
    final parts = header.split(';');
    if (parts.isEmpty) return null;

    final pair = parts.first;
    final eq = pair.indexOf('=');
    if (eq <= 0) return null;
    final name = pair.substring(0, eq).trim();
    final value = pair.substring(eq + 1).trim();
    if (name.isEmpty) return null;

    String? domainAttr;
    String? pathAttr;
    var secure = false;
    DateTime? expires;
    int? maxAge;

    for (final attr in parts.skip(1)) {
      final trimmed = attr.trim();
      final split = trimmed.indexOf('=');
      final key = (split < 0 ? trimmed : trimmed.substring(0, split))
          .trim()
          .toLowerCase();
      final attrValue = split < 0 ? '' : trimmed.substring(split + 1).trim();

      switch (key) {
        case 'domain':
          if (attrValue.isNotEmpty) {
            domainAttr = attrValue
                .replaceFirst(RegExp(r'^\.'), '')
                .toLowerCase();
          }
        case 'path':
          if (attrValue.startsWith('/')) pathAttr = attrValue;
        case 'secure':
          secure = true;
        case 'max-age':
          maxAge = int.tryParse(attrValue);
        case 'expires':
          expires = _parseExpires(attrValue);
      }
    }

    // Max-Age takes precedence over Expires (RFC 6265 section 5.3).
    if (maxAge != null) {
      // Max-Age <= 0 must land strictly in the past: now + 0 reads as unexpired.
      expires = maxAge <= 0
          ? DateTime.utc(1970)
          : DateTime.now().toUtc().add(Duration(seconds: maxAge));
    }

    final host = uri.host.toLowerCase();
    if (domainAttr != null &&
        host != domainAttr &&
        !host.endsWith('.$domainAttr')) {
      return null;
    }

    return StoredCookie(
      name: name,
      value: value,
      domain: domainAttr ?? host,
      path: pathAttr ?? _defaultPath(uri),
      hostOnly: domainAttr == null,
      secure: secure,
      expires: expires,
    );
  }

  /// An unreadable Expires leaves the cookie as a session cookie.
  static DateTime? _parseExpires(String raw) {
    if (raw.isEmpty) return null;
    try {
      return _httpDate(raw);
    } on FormatException {
      return null;
    }
  }

  static const List<String> _months = <String>[
    'jan',
    'feb',
    'mar',
    'apr',
    'may',
    'jun',
    'jul',
    'aug',
    'sep',
    'oct',
    'nov',
    'dec',
  ];

  /// Parses the date formats RFC 7231 allows in a Set-Cookie Expires.
  static DateTime _httpDate(String raw) {
    final match = RegExp(
      r'(\d{1,2})[ -]([A-Za-z]{3})[ -](\d{2,4})\s+(\d{2}):(\d{2}):(\d{2})',
    ).firstMatch(raw);
    if (match == null) throw FormatException('unrecognised date', raw);

    final day = int.parse(match.group(1)!);
    final month = _months.indexOf(match.group(2)!.toLowerCase()) + 1;
    if (month == 0) throw FormatException('unrecognised month', raw);

    var year = int.parse(match.group(3)!);
    if (year < 70) {
      year += 2000;
    } else if (year < 100) {
      year += 1900;
    }

    return DateTime.utc(
      year,
      month,
      day,
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.parse(match.group(6)!),
    );
  }
}
