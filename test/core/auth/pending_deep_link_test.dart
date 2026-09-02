import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/core/auth/pending_deep_link_controller.dart';
import 'package:notes_insa/providers/auth_providers.dart';

void main() {
  late ProviderContainer container;
  late List<String> delivered;
  late PendingDeepLinkController controller;

  setUp(() {
    container = ProviderContainer();
    delivered = <String>[];
    controller = PendingDeepLinkController(container, onDeliver: delivered.add);
  });

  tearDown(() {
    controller.dispose();
    container.dispose();
  });

  test('every payload type is withheld while locked', () {
    for (final payload in const [
      'reauth_required',
      'new_grades',
      'updated_grades',
      'background_refresh_failed',
    ]) {
      controller.submit(payload);
    }
    expect(delivered, isEmpty);
  });

  test('the buffered payload is delivered once unlocked', () {
    controller.submit('reauth_required');
    expect(delivered, isEmpty);
    container.read(gradesUnlockedProvider.notifier).state = true;
    expect(delivered, <String>['reauth_required']);
  });

  test('only the most recent payload is retained', () {
    controller.submit('new_grades');
    controller.submit('reauth_required');
    container.read(gradesUnlockedProvider.notifier).state = true;
    expect(delivered, <String>['reauth_required']);
  });

  test('a payload arriving while unlocked is delivered immediately', () {
    container.read(gradesUnlockedProvider.notifier).state = true;
    controller.submit('new_grades');
    expect(delivered, <String>['new_grades']);
  });

  test('the buffer is not redelivered on a second unlock', () {
    controller.submit('new_grades');
    container.read(gradesUnlockedProvider.notifier).state = true;
    container.read(gradesUnlockedProvider.notifier).state = false;
    container.read(gradesUnlockedProvider.notifier).state = true;
    expect(delivered, <String>['new_grades']);
  });
}
