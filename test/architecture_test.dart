import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Structural guards. These are cheaper than code review and do not rot.
void main() {
  final modulesDir = Directory('lib/modules');
  final libDir = Directory('lib');

  List<File> dartFilesUnder(Directory dir) => dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  String posix(File f) => f.path.replaceAll(Platform.pathSeparator, '/');

  /// lib/theme owns every literal design value. These two screens keep a fixed
  /// palette for a documented reason: camera chrome painted over a live feed,
  /// and a developer-only terminal view.
  const paletteExceptions = <String>{
    'lib/screens/scan_screen.dart',
    'lib/modules/grades/raw_json_viewer_screen.dart',
  };

  bool ownsDesignValues(File f) {
    final path = posix(f);
    return path.startsWith('lib/theme/') || paletteExceptions.contains(path);
  }

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

  test('design values live only in lib/theme', () {
    final failures = <String>[];
    final patterns = <String, RegExp>{
      'a raw Color literal': RegExp(r'Color\(0x'),
      'a TextStyle constructor': RegExp(r'(?<!\.)\bTextStyle\('),
      'a literal Radius.circular': RegExp(r'Radius\.circular\(\s*\d'),
    };
    for (final file in dartFilesUnder(libDir)) {
      if (ownsDesignValues(file)) continue;
      final source = file.readAsStringSync();
      patterns.forEach((what, pattern) {
        if (pattern.hasMatch(source)) failures.add('${posix(file)}: $what');
      });
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  test('widgets use theme colours, never the Colors palette', () {
    final failures = <String>[];
    // Colors.transparent has no theme equivalent and carries no design intent.
    final banned = RegExp(r'\bColors\.(?!transparent\b)\w+');
    for (final file in dartFilesUnder(libDir)) {
      if (ownsDesignValues(file)) continue;
      for (final match in banned.allMatches(file.readAsStringSync())) {
        failures.add('${posix(file)}: ${match.group(0)}');
      }
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  test('no gradients or shadows survive outside the theme', () {
    final failures = <String>[];
    final banned = RegExp(
      r'LinearGradient|RadialGradient|SweepGradient|BoxShadow',
    );
    for (final file in dartFilesUnder(libDir)) {
      if (posix(file).startsWith('lib/theme/')) continue;
      if (banned.hasMatch(file.readAsStringSync())) {
        failures.add(posix(file));
      }
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  });
}
