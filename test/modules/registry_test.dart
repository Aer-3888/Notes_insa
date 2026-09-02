import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/modules/registry.dart';

void main() {
  test('module ids are unique', () {
    final ids = kCampusModules.map((m) => m.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('every module has non-empty French copy', () {
    for (final m in kCampusModules) {
      expect(m.label, isNotEmpty, reason: 'module ${m.id} has no label');
      if (m is ComingSoonModule) {
        expect(m.teaser, isNotEmpty, reason: 'module ${m.id} has no teaser');
      }
    }
  });

  test('only ready modules can require CAS', () {
    // Encoded by the type system: requiresCas exists only on ReadyModule.
    // This test documents the invariant and fails if the hierarchy is flattened.
    for (final m in kCampusModules) {
      switch (m) {
        case ReadyModule():
          expect(m.requiresCas, isA<bool>());
        case ComingSoonModule():
          expect(m, isNot(isA<ReadyModule>()));
      }
    }
  });

  test('the grades module is the only CAS-gated one in this phase', () {
    final gated = kCampusModules
        .whereType<ReadyModule>()
        .where((m) => m.requiresCas)
        .map((m) => m.id);
    expect(gated, <String>['notes']);
  });
}
