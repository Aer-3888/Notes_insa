import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_providers.dart';

/// Buffers notification deep links until the grades module is unlocked.
///
/// Every payload is withheld, not only the navigational one. The fetch payloads
/// populate grade state in memory, and the reauth payload leads to a screen that
/// can wipe stored credentials.
class PendingDeepLinkController {
  PendingDeepLinkController(this._container, {required this.onDeliver}) {
    _subscription = _container.listen<bool>(gradesUnlockedProvider, (
      _,
      unlocked,
    ) {
      if (unlocked) _flush();
    });
  }

  final ProviderContainer _container;
  final void Function(String payload) onDeliver;

  late final ProviderSubscription<bool> _subscription;
  String? _pending;

  void submit(String payload) {
    if (_container.read(gradesUnlockedProvider)) {
      onDeliver(payload);
      return;
    }
    _pending = payload;
  }

  void _flush() {
    final payload = _pending;
    if (payload == null) return;
    _pending = null;
    onDeliver(payload);
  }

  void dispose() => _subscription.close();
}
