import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/providers/dashboard_providers.dart';

void main() {
  test('defaults to the newest available semester until one is chosen', () {
    final container = ProviderContainer(
      overrides: [
        availableSemestersProvider.overrideWith(
          (ref) => const <int>[1, 2, 3, 4, 5, 6],
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(effectiveSemesterProvider), 6);

    container.read(selectedSemesterProvider.notifier).state = 3;
    expect(container.read(effectiveSemesterProvider), 3);
  });
}
