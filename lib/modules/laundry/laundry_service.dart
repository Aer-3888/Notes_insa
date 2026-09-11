import '../../constants.dart';
import '../../services/resilient_http.dart';
import 'laundry_model.dart';

/// Reads live laundry status from the Notes INSA Worker, which proxies and
/// caches WASHiN (see worker/src/laundry.ts). Credentials never reach the app.
class LaundryService {
  const LaundryService();

  static final Uri _endpoint = Uri.parse('$kWorkerBaseUrl/laundry');

  Future<LaundryStatus> fetch() async {
    final response = await ResilientHttp.get(
      _endpoint,
      headers: <String, String>{'X-App-Secret': kAppSecret},
      timeout: const Duration(seconds: 12),
    );
    final decoded = ResilientHttp.decodeJson(response);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Laundry status unavailable (${response?.statusCode})');
    }
    return LaundryStatus.fromJson(decoded);
  }
}
