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
import 'package:notes_insa/services/mdw/mdw_client.dart';
import 'package:notes_insa/services/mdw/vaadin_nodes.dart';

Future<void> main(List<String> args) async {
  final raw = args.contains('--raw');
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

    stdout.writeln('\n> openGrades(0)');
    final data = await mdw.openGrades(0);
    stdout.writeln('  ${data.describe()}');
    stdout.writeln('  grid=${mdw.gridNode} close=${mdw.closeButtonNode}');

    await mdw.closeGrades();
    await mdw.dispose();
  } on Object catch (e) {
    stdout.writeln('\nFAILED: $e');
    exitCode = 1;
  } finally {
    cas.close();
  }

  for (final MapEntry<String, Map<String, dynamic>> entry in captures.entries) {
    final file = File('${outDir.path}/${entry.key}.json');
    final content = raw ? entry.value : _redact(entry.value);
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
