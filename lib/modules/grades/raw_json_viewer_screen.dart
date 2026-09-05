import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';
import '../../theme/state_view.dart';
import 'grades_provider.dart';

// Developer screen. Its terminal palette is deliberate and stays fixed in both
// themes; it is reachable only after seven taps on the version row.
// Syntax highlight colors (dark terminal palette)
const _colorKey = Color(0xFF82AAFF); // blue — JSON keys
const _colorString = Color(0xFFC3E88D); // green — string values
const _colorNumber = Color(0xFFF78C6C); // orange — numbers
const _colorBoolNull = Color(0xFFFFCB6B); // amber — true / false / null
const _colorPunct = Color(0xFF89929B); // grey — colons, commas, braces
const _colorBase = Colors.white70;

const _baseStyle = TextStyle(
  fontFamily: 'monospace',
  fontSize: 12,
  height: 1.5,
  color: _colorBase,
);

TextStyle _valueStyle(String value) {
  if (value.startsWith('"')) return _baseStyle.copyWith(color: _colorString);
  if (value == 'true' || value == 'false') {
    return _baseStyle.copyWith(color: _colorBoolNull);
  }
  if (value == 'null') return _baseStyle.copyWith(color: _colorPunct);
  if (RegExp(r'^-?\d+(\.\d+)?$').hasMatch(value)) {
    return _baseStyle.copyWith(color: _colorNumber);
  }
  return _baseStyle.copyWith(color: _colorBase);
}

List<InlineSpan> _highlightValue(String raw) {
  final trimmed = raw.trimRight();
  // Structural: {, [, ], }, etc.
  if (RegExp(r'^[\[\]{},]*$').hasMatch(trimmed)) {
    return [
      TextSpan(
        text: raw,
        style: _baseStyle.copyWith(color: _colorPunct),
      ),
    ];
  }
  final hasComma = trimmed.endsWith(',');
  final core = hasComma ? trimmed.substring(0, trimmed.length - 1) : trimmed;
  final trailing = raw.substring(trimmed.length);
  return [
    TextSpan(text: core, style: _valueStyle(core)),
    if (hasComma)
      TextSpan(
        text: ',',
        style: _baseStyle.copyWith(color: _colorPunct),
      ),
    if (trailing.isNotEmpty) TextSpan(text: trailing, style: _baseStyle),
  ];
}

List<InlineSpan> _highlightLine(String line) {
  final keyValue = RegExp(
    r'^(\s*)("(?:[^"\\]|\\.)*")(\s*:\s*)(.*)$',
  ).firstMatch(line);

  if (keyValue != null) {
    final indent = keyValue.group(1)!;
    final key = keyValue.group(2)!;
    final colon = keyValue.group(3)!;
    final value = keyValue.group(4)!;
    return [
      TextSpan(text: indent, style: _baseStyle),
      TextSpan(
        text: key,
        style: _baseStyle.copyWith(color: _colorKey),
      ),
      TextSpan(
        text: colon,
        style: _baseStyle.copyWith(color: _colorPunct),
      ),
      ..._highlightValue(value),
    ];
  }

  // Array values or structural lines
  final trimmed = line.trim();
  return [
    TextSpan(text: line, style: _valueStyle(trimmed.replaceAll(',', ''))),
  ];
}

TextSpan _buildHighlightedJson(String jsonStr) {
  final lines = jsonStr.split('\n');
  final spans = <InlineSpan>[];
  for (int i = 0; i < lines.length; i++) {
    spans.addAll(_highlightLine(lines[i]));
    if (i < lines.length - 1) spans.add(const TextSpan(text: '\n'));
  }
  return TextSpan(children: spans);
}

class RawJsonViewerScreen extends ConsumerWidget {
  const RawJsonViewerScreen({super.key});

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
  }

  String _formatJson(String jsonStr) {
    try {
      final decoded = jsonDecode(jsonStr);
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(decoded);
    } catch (_) {
      return jsonStr;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gradesState = ref.watch(gradesProvider);
    final jsonString = gradesState.jsonData;
    final formattedJson = _formatJson(jsonString);
    final isEmpty = jsonString == '{}' || jsonString.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('JSON brut'),
        actions: [
          if (!isEmpty)
            IconButton(
              icon: const Icon(Icons.copy),
              onPressed: () => _copyToClipboard(jsonString),
              tooltip: 'Copier le JSON',
            ),
        ],
      ),
      body: isEmpty
          ? const StateView(
              icon: Icons.inbox_outlined,
              title: 'Aucune donnée disponible',
              body: 'Connectez-vous pour charger vos notes.',
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Info card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'JSON des notes, '
                            '${(jsonString.length / 1024).toStringAsFixed(1)} KB',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Highlighted JSON
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E2E),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF313244)),
                    ),
                    child: SelectableText.rich(
                      _buildHighlightedJson(formattedJson),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
    );
  }
}
