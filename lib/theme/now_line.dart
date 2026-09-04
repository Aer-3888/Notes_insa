import 'package:flutter/material.dart';

import 'campus_context.dart';

/// The signature: a 3 dp accent line with a dot at its start. Drawn across
/// the timetable at the current time and reused wherever "now" is marked.
class NowLine extends StatelessWidget {
  const NowLine({super.key, this.semanticsLabel = 'Maintenant'});

  final String semanticsLabel;

  static const double thickness = 3;
  static const double dot = 8;

  @override
  Widget build(BuildContext context) {
    final color = context.campus.now;
    return Semantics(
      label: semanticsLabel,
      child: SizedBox(
        height: dot,
        child: Row(
          children: [
            SizedBox(
              width: dot,
              height: dot,
              child: DecoratedBox(
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ),
            Expanded(
              child: Center(
                child: SizedBox(
                  height: thickness,
                  width: double.infinity,
                  child: ColoredBox(color: color),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
