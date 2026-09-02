import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Structural guards. These are cheaper than code review and do not rot.
void main() {
  final modulesDir = Directory('lib/modules');

  List<File> dartFilesUnder(Directory dir) => dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  test('no module imports another module', () {
    final failures = <String>[];
    for (final entry in modulesDir.listSync().whereType<Directory>()) {
      final owner = entry.path.split(Platform.pathSeparator).last;
      for (final file in dartFilesUnder(entry)) {
        for (final line in file.readAsLinesSync()) {
          final match = RegExp(r"import\s+'([^']+)'").firstMatch(line);
          if (match == null) continue;
          final target = match.group(1)!;
          final crosses = RegExp(
            r'modules/([A-Za-z0-9_]+)/',
          ).firstMatch(target);
          if (crosses != null && crosses.group(1) != owner) {
            failures.add('${file.path} imports $target');
          }
        }
      }
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  test('the grades module never touches the plaintext module cache', () {
    final gradesDir = Directory('lib/modules/grades');
    if (!gradesDir.existsSync()) return;
    final failures = <String>[];
    for (final file in dartFilesUnder(gradesDir)) {
      final source = file.readAsStringSync();
      if (source.contains('core/module_cache.dart') ||
          source.contains('package:shared_preferences/')) {
        failures.add(file.path);
      }
    }
    expect(
      failures,
      isEmpty,
      reason: 'grade data must stay in secure storage:\n${failures.join('\n')}',
    );
  });
}
