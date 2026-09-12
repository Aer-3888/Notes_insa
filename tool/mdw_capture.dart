// Captures the raw Vaadin responses MDW returns for a grade page.
//
//   dart run tool/mdw_capture.dart [--out <dir>] [--raw]
//
// Signs in through the CAS, opens the first grade card, and writes every UIDL
// response to disk so the parser can be written against what MDW actually
// sends. Values are redacted unless --raw is passed: the default dump keeps
// key names, types and sizes only, which is enough to locate the rows.
import 'dart:convert';
import 'dart:io';

import 'package:notes_insa/services/cas/cas_client.dart';
import 'package:notes_insa/services/mdw/grade.dart';
import 'package:notes_insa/services/mdw/grade_parser.dart';
import 'package:notes_insa/services/mdw/mdw_client.dart';
import 'package:notes_insa/services/mdw/vaadin_nodes.dart';
import 'package:notes_insa/services/mdw/vaadin_types.dart';

Future<void> main(List<String> args) async {
  final reparseIndex = args.indexOf('--reparse');
  if (reparseIndex >= 0 && reparseIndex + 1 < args.length) {
    _reparse(args[reparseIndex + 1]);
    return;
  }

  final raw = args.contains('--raw');
  final show = args.contains('--show');
  final outIndex = args.indexOf('--out');
  final outDir = Directory(
    outIndex >= 0 && outIndex + 1 < args.length
        ? args[outIndex + 1]
        : 'mdw_capture',
  );
  outDir.createSync(recursive: true);

  final captures = <String, Map<String, dynamic>>{};
  var counter = 0;

  final cas = CasClient();
  try {
    final username = _prompt('Identifiant INSA');
    final password = _promptSecret('Mot de passe');

    stdout.writeln('\n> auth');
    await cas.auth(username, password);

    if (cas.isTokenNeeded) {
      stdout.writeln('  second factor required');
      stdout.writeln('  1) code by e-mail   2) authenticator code');
      if (_prompt('Choice [1/2]').trim() == '1') {
        await cas.triggerEmail();
        await cas.validate(_prompt('Code received').trim());
      } else {
        await cas.validate(_prompt('Code').trim());
      }
    }
    stdout.writeln('  signed in');

    final mdw = MdwClient(
      cas.session,
      onResponse: (String label, Map<String, dynamic> body) {
        captures['${(counter++).toString().padLeft(2, '0')}-$label'] = body;
      },
    );

    stdout.writeln('\n> init');
    await mdw.init();
    stdout.writeln(
      '  uiId=${mdw.session.uiId} '
      'beat=${mdw.session.beatIntervalSeconds}s',
    );

    stdout.writeln('\n> loadGroups');
    final count = await mdw.loadGroups();
    stdout.writeln('  $count grade card(s)');
    if (count == 0) {
      stdout.writeln('  nothing to open; stopping');
      return;
    }

    stdout.writeln('\n> openAllRows(0)');
    final data = await mdw.openAllRows(0);
    stdout.writeln('  ${data.describe()}');
    stdout.writeln('  grid=${mdw.gridNode} close=${mdw.closeButtonNode}');
    stdout.writeln('  size=${data.gridSize} blanked=${data.clearedRanges}');
    stdout.writeln('  grid publishes: ${data.publishedMethods(mdw.gridNode)}');
    stdout.writeln(
      '  using range=${mdw.rangeMethod.isEmpty ? 'NONE' : mdw.rangeMethod} '
      'children=${mdw.childRangeMethod.isEmpty ? 'NONE' : mdw.childRangeMethod}',
    );

    // Parsed from memory, where the values are still intact; the files on disk
    // are redacted separately.
    stdout.writeln('\n> parse');
    _report(data, show: show);

    await mdw.closeGrades();
    await mdw.dispose();
  } on Object catch (e) {
    stdout.writeln('\nFAILED: $e');
    exitCode = 1;
  } finally {
    cas.close();
  }

  for (final MapEntry<String, Map<String, dynamic>> entry in captures.entries) {
    final hits = <String>[];
    _findGradeItems(entry.value, entry.key, hits);
    if (hits.isNotEmpty) {
      stdout.writeln('\nGRADE ROWS in ${entry.key}:');
      for (final String hit in hits.take(8)) {
        stdout.writeln('  $hit');
      }
      if (hits.length > 8) stdout.writeln('  ... ${hits.length - 8} more');
    }
  }

  for (final MapEntry<String, Map<String, dynamic>> entry in captures.entries) {
    final file = File('${outDir.path}/${entry.key}.json');
    final content = raw ? entry.value : _redactResponse(entry.value);
    file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(content));
    stdout.writeln('wrote ${file.path}');
  }

  if (!raw) {
    stdout.writeln(
      '\nValues are redacted. Re-run with --raw if the shape alone is not '
      'enough, and review before sharing.',
    );
  }
}

/// Reports what the parser made of a response. Prints only shapes and lengths
/// unless [show] is set, so the marks stay on this machine by default.
void _report(VaadinData data, {required bool show}) {
  final rows = GradeParser.rowsOf(data);
  final missing = GradeParser.missingChildKeys(rows);
  final size = data.gridSize;
  stdout.writeln(
    '  ${rows.length} rows of ${size ?? '?'}, '
    '${missing.isEmpty ? 'no' : missing.length} missing child set(s)',
  );
  // The grid counts only the children it has already fetched, so its size is a
  // floor rather than a target. Falling short of it is still a bad sign.
  if (size != null && rows.length < size) {
    stdout.writeln('  SHORT: ${size - rows.length} row(s) below the last size');
    exitCode = 1;
  }
  if (missing.isNotEmpty) {
    stdout.writeln('  ${missing.length} parent(s) still claim unfetched rows');
    exitCode = 1;
  }

  final root = GradeParser.parse(data);
  if (root == null) {
    stdout.writeln('  FAILED: no grade tree');
    exitCode = 1;
    return;
  }

  var nodes = 0;
  var deepest = 0;
  var scored = 0;
  root.forEach((int depth, Grade grade) {
    nodes++;
    if (depth > deepest) deepest = depth;
    if (grade.score.isNotEmpty) scored++;
  });

  stdout.writeln('  OK: $nodes nodes, depth $deepest, $scored with a result');

  if (!show) {
    stdout.writeln(
      '\n  Shape only (pass --show to print the tree and check '
      'it against your real marks):',
    );
    root.forEach((int depth, Grade grade) {
      stdout.writeln(
        '  ${'  ' * depth}name(${grade.name.length}) '
        'score(${grade.score.length})',
      );
    });
    return;
  }

  stdout.writeln('');
  root.forEach((int depth, Grade grade) {
    final score = grade.score.isEmpty ? '' : '   ${grade.score.join(' | ')}';
    stdout.writeln('  ${'  ' * depth}${grade.name}$score');
  });
}

/// Re-runs the parser over a saved dump, so a capture can be re-examined
/// without signing in again.
void _reparse(String path) {
  final decoded = jsonDecode(File(path).readAsStringSync());
  if (decoded is! Map<String, dynamic>) {
    stdout.writeln('not a UIDL response: $path');
    exitCode = 1;
    return;
  }

  final data = VaadinData.fromJson(decoded);
  final rows = GradeParser.rowsOf(data);
  stdout.writeln(
    '${data.changes.length} changes, ${data.execute.length} '
    'calls, ${rows.length} rows of ${data.gridSize ?? '?'}',
  );
  for (final ({int length, int start}) gap in data.clearedRanges) {
    stdout.writeln('rows ${gap.start}..${gap.start + gap.length - 1} not sent');
  }

  final missing = GradeParser.missingChildKeys(rows);
  if (missing.isNotEmpty) {
    stdout.writeln('children still to request: ${missing.join(', ')}');
  }

  final root = GradeParser.parse(data);
  if (root == null) {
    stdout.writeln('no grade tree');
    exitCode = 1;
    return;
  }

  var count = 0;
  root.forEach((int depth, Grade grade) {
    count++;
    final score = grade.score.isEmpty ? '' : '  ${grade.score.join(' | ')}';
    stdout.writeln('${'  ' * depth}${grade.name}$score');
  });
  stdout.writeln('\n$count nodes parsed');
}

/// Walks the whole response looking for grid rows, so the parser can be
/// pointed at wherever MDW puts them rather than where it used to.
///
/// A row is an object carrying a "key" plus at least one "lr_" column.
void _findGradeItems(Object? value, String path, List<String> hits) {
  if (value is Map) {
    final hasKey = value['key'] is String;
    final hasColumn = value.keys.any((Object? k) => '$k'.startsWith('lr_'));
    if (hasKey && hasColumn) {
      final columns = value.keys.where((Object? k) => '$k'.startsWith('lr_'));
      hits.add(
        '$path  (${value.length} fields, columns: '
        '${columns.join(', ')})',
      );
      return;
    }
    for (final MapEntry<Object?, Object?> e in value.entries) {
      _findGradeItems(e.value, '$path.${e.key}', hits);
    }
    return;
  }
  if (value is List) {
    for (var i = 0; i < value.length; i++) {
      _findGradeItems(value[i], '$path[$i]', hits);
    }
  }
}

/// Redacts a response but keeps the JS expression each `execute` call ends
/// with. Those name the grid operations, so a dump without them cannot be told
/// a paged read from a complete one.
Object? _redactResponse(Map<String, dynamic> body) {
  final out = <String, dynamic>{};
  for (final MapEntry<String, dynamic> entry in body.entries) {
    final Object? value = entry.value;
    if (entry.key == 'changes' && value is List) {
      out[entry.key] = value.map(_redactChange).toList();
      continue;
    }
    if (entry.key != 'execute' || value is! List) {
      out[entry.key] = _redact(value);
      continue;
    }
    out[entry.key] = value.map((Object? call) {
      if (call is! List || call.isEmpty || call.last is! String) {
        return _redact(call);
      }
      return <Object?>[...call.take(call.length - 1).map(_redact), call.last];
    }).toList();
  }
  return out;
}

/// Redacts a node change but keeps the framework's own vocabulary: the change
/// type, the property name, a component tag, and the names of the methods the
/// client may call. None of those carry anything of the user's.
Object? _redactChange(Object? change) {
  if (change is! Map) return _redact(change);

  final out = <String, dynamic>{};
  for (final MapEntry<Object?, Object?> entry in change.entries) {
    final key = '${entry.key}';
    final Object? value = entry.value;
    out[key] = switch (key) {
      'type' || 'key' || 'feat' || 'node' || 'index' => value,
      'value' when change['key'] == 'tag' => value,
      'add' when change['feat'] == 19 => value,
      _ => _redact(value),
    };
  }
  return out;
}

/// Replaces leaf values with a type tag, keeping structure and key names.
Object? _redact(Object? value) {
  if (value is Map) {
    return <String, dynamic>{
      for (final MapEntry<Object?, Object?> e in value.entries)
        '${e.key}': _redact(e.value),
    };
  }
  if (value is List) {
    return value.map(_redact).toList();
  }
  if (value is String) return 'str(${value.length})';
  if (value is num) return value;
  return value;
}

String _prompt(String label) {
  stdout.write('$label: ');
  return stdin.readLineSync(encoding: utf8) ?? '';
}

String _promptSecret(String label) {
  stdout.write('$label: ');
  final echoing = stdin.hasTerminal && stdin.echoMode;
  if (echoing) stdin.echoMode = false;
  try {
    return stdin.readLineSync(encoding: utf8) ?? '';
  } finally {
    if (echoing) stdin.echoMode = true;
    stdout.writeln();
  }
}
