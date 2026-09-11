/// The hosts the CAS sign-in talks to. A value object so tests can point the
/// flow at a fake server; production uses [CasEndpoints.insa].
class CasEndpoints {
  const CasEndpoints({
    this.casBaseUrl = 'https://cas.insa-rennes.fr/cas/login',
    this.otpBaseUrl = 'https://otp-api.insa-rennes.fr',
    this.service = 'https://mdw.insa-rennes.fr/login/cas',
    this.sessionHosts = defaultSessionHosts,
  });

  /// Must stay spelled exactly as the native bridge spells them, or its
  /// `ImportCAS` silently restores nothing.
  static const List<String> defaultSessionHosts = <String>[
    'https://cas.insa-rennes.fr/cas/login',
    'https://mdw.insa-rennes.fr',
  ];

  final List<String> sessionHosts;

  /// The CAS login form.
  final String casBaseUrl;

  /// The OTP service that mails one-time codes.
  final String otpBaseUrl;

  /// MDW only sets its own session cookie once the CAS redirects back here.
  final String service;

  static const CasEndpoints insa = CasEndpoints();

  Uri get loginUri =>
      Uri.parse(casBaseUrl).replace(queryParameters: {'service': service});

  /// Without the service parameter the CAS answers an established session
  /// with a "Log In Successful" page.
  Uri get statusUri => Uri.parse(casBaseUrl);

  String get casHost => Uri.parse(casBaseUrl).host;

  Uri mailCodeUri(String username, String userHash) => Uri.parse(
    '$otpBaseUrl/users/$username/methods/random_code_mail/transports/mail/'
    '$userHash',
  );
}
