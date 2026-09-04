import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/core/freshness.dart';
import 'package:notes_insa/core/module_cache.dart';

void main() {
  final at = DateTime(2026, 9, 3, 18, 40);

  test('fresh and refreshing carry no timestamp', () {
    expect(freshnessLabel(RefreshState.fresh, at), 'À jour');
    expect(freshnessLabel(RefreshState.refreshing, at), 'Actualisation…');
  });

  test('failures name the state and the cache time', () {
    expect(
      freshnessLabel(RefreshState.failedOffline, at),
      'Hors ligne (3/9 18:40)',
    );
    expect(
      freshnessLabel(RefreshState.failedUpstream, at),
      'Service indisponible (3/9 18:40)',
    );
  });

  test('a failure with no cache time has no parenthesis', () {
    expect(freshnessLabel(RefreshState.failedOffline, null), 'Hors ligne');
  });
}
