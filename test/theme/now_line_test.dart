import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/theme/campus_theme.dart';
import 'package:notes_insa/theme/now_line.dart';
import 'package:notes_insa/theme/tokens.dart';

void main() {
  testWidgets('renders in the accent colour with a semantics label', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: campusTheme(Brightness.light),
        home: const Scaffold(body: NowLine()),
      ),
    );
    expect(find.bySemanticsLabel('Maintenant'), findsOneWidget);
    final boxes = tester.widgetList<ColoredBox>(find.byType(ColoredBox));
    expect(boxes.map((b) => b.color), contains(CampusColors.light.now));
  });
}
