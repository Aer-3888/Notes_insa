part of '../dashboard_screen.dart';

// ---------------------------------------------------------------------------
// Subject stats bottom sheet
// ---------------------------------------------------------------------------

class _SubjectStatsSheet extends StatelessWidget {
  final Subject subject;
  final SubjectAverage? avg;

  const _SubjectStatsSheet({required this.subject, required this.avg});

  @override
  Widget build(BuildContext context) {
    final averagePrefix = subject.isAverageEstimated ? '≈' : '';
    final averageText = subject.average == null
        ? null
        : '$averagePrefix${subject.average!.toStringAsFixed(2)}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CampusSpacing.gutter,
        0,
        CampusSpacing.gutter,
        CampusSpacing.x8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header: subject name + user grade
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titleCase(subject.name),
                      style: context.text.titleLarge,
                    ),
                    const SizedBox(height: CampusSpacing.x1),
                    averageText != null
                        ? Text(
                            'Ma note : $averageText',
                            style: context.campusType.numeral.copyWith(
                              color:
                                  GradeUtils.needsAttention(
                                    subject.average,
                                    null,
                                  )
                                  ? context.scheme.error
                                  : context.scheme.onSurface,
                            ),
                          )
                        : Text(
                            'Pas encore de note',
                            style: context.text.bodyMedium?.copyWith(
                              color: context.scheme.onSurfaceVariant,
                            ),
                          ),
                  ],
                ),
              ),
              _CoeffChip(coeff: subject.coeff),
            ],
          ),
          const SizedBox(height: CampusSpacing.x5),
          // Histogram or placeholder
          if (avg == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: CampusSpacing.x8),
              child: StateView(
                icon: Icons.bar_chart_outlined,
                title: 'Statistiques non disponibles',
                body:
                    'Personne n’a encore partagé de notes pour cette matière.',
              ),
            )
          else
            SizedBox(
              height: 180,
              child: _GradeHistogram(
                buckets: avg!.buckets,
                myGrade: subject.average,
              ),
            ),
          const SizedBox(height: CampusSpacing.x5),
          // Stats row
          if (avg != null)
            Row(
              children: [
                _StatCell(label: 'Moyenne', value: avg!.avg.toStringAsFixed(2)),
                _StatDivider(),
                _StatCell(
                  label: 'Médiane',
                  value: avg!.median.toStringAsFixed(1),
                ),
                _StatDivider(),
                _StatCell(label: 'Min', value: avg!.min.toStringAsFixed(2)),
                _StatDivider(),
                _StatCell(label: 'Max', value: avg!.max.toStringAsFixed(2)),
                _StatDivider(),
                _StatCell(label: 'Effectif', value: avg!.count.toString()),
              ],
            ),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  final String label;
  final String value;

  const _StatCell({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: context.campusType.numeral),
          const SizedBox(height: CampusSpacing.x1),
          Text(
            label,
            style: context.text.labelMedium?.copyWith(
              color: context.scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: CampusSpacing.x8,
    color: context.scheme.outlineVariant,
  );
}

// ---------------------------------------------------------------------------
// Grade histogram (CustomPainter)
// ---------------------------------------------------------------------------

class _GradeHistogram extends StatelessWidget {
  final List<int> buckets;
  final double? myGrade;

  const _GradeHistogram({required this.buckets, this.myGrade});

  static int? _bucketIndex(double grade) {
    if (grade < 0 || grade > 20) return null;
    return grade.floor().clamp(0, 19);
  }

  @override
  Widget build(BuildContext context) {
    final myBucket = myGrade != null ? _bucketIndex(myGrade!) : null;
    final total = buckets.fold<int>(0, (a, b) => a + b);
    final below = myBucket == null
        ? 0
        : buckets.take(myBucket).fold<int>(0, (a, b) => a + b);
    // A bar chart is invisible to a screen reader, so state the one fact it
    // carries: where this student sits in the cohort.
    final summary = myBucket == null || total == 0
        ? 'Répartition des notes de la promo'
        : 'Répartition des notes de la promo. '
              'Votre note dépasse ${(below * 100 / total).round()} % '
              'des notes partagées.';

    return Semantics(
      label: summary,
      excludeSemantics: true,
      child: CustomPaint(
        painter: _HistogramPainter(
          buckets: buckets,
          myBucket: myBucket,
          barColor: context.scheme.surfaceContainerHighest,
          myBarColor: context.campus.now,
          labelColor: context.scheme.onSurfaceVariant,
          labelStyle: context.text.labelMedium!,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _HistogramPainter extends CustomPainter {
  final List<int> buckets;
  final int? myBucket;
  final Color barColor;
  final Color myBarColor;
  final Color labelColor;
  final TextStyle labelStyle;

  _HistogramPainter({
    required this.buckets,
    required this.myBucket,
    required this.barColor,
    required this.myBarColor,
    required this.labelColor,
    required this.labelStyle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const labelHeight = 24.0;
    const barInset = 1.5; // gap between tick and bar edge

    final maxCount = buckets.fold<int>(0, (m, b) => b > m ? b : m);
    if (maxCount == 0) return;

    final n = buckets.length; // 20
    // Each bar occupies an equal slot; label centered under bar center
    final slotWidth = size.width / n;
    final barWidth = slotWidth - barInset * 2;

    final barPaint = Paint()..style = PaintingStyle.fill;
    final labels = labelStyle.copyWith(color: labelColor);
    final markerPaint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < n; i++) {
      final slotCenter = i * slotWidth + slotWidth / 2;
      final barLeft = slotCenter - barWidth / 2;
      final count = buckets[i];

      // Bar
      double barH = count == 0
          ? 0
          : (count / maxCount) * (size.height - labelHeight);
      if (count > 0 && barH < 4) barH = 4;

      final isMyBar = myBucket == i;
      barPaint.color = isMyBar ? myBarColor : barColor;

      if (barH > 0) {
        final top = size.height - labelHeight - barH;
        final rect = RRect.fromRectAndCorners(
          Rect.fromLTWH(barLeft, top, barWidth, barH),
          topLeft: const Radius.circular(3),
          topRight: const Radius.circular(3),
        );
        canvas.drawRRect(rect, barPaint);

        // Triangle marker above user's bar
        if (isMyBar) {
          markerPaint.color = myBarColor;
          const markerSize = 6.0;
          final path = Path()
            ..moveTo(slotCenter - markerSize / 2, top - 6)
            ..lineTo(slotCenter + markerSize / 2, top - 6)
            ..lineTo(slotCenter, top - 1)
            ..close();
          canvas.drawPath(path, markerPaint);
        }
      }

      // Label every 2 bars: 0, 2, 4, ..., 18
      if (i % 2 == 0 && i < n - 1) {
        final label = i.toString();
        final tp = TextPainter(
          text: TextSpan(text: label, style: labels),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(slotCenter - tp.width / 2, size.height - labelHeight + 4),
        );
      }
    }

    // "20" centered under the last bar (bar 19 = [19,20])
    final lastSlotCenter = (n - 1) * slotWidth + slotWidth / 2;
    final tp20 = TextPainter(
      text: TextSpan(text: '20', style: labels),
      textDirection: TextDirection.ltr,
    )..layout();
    tp20.paint(
      canvas,
      Offset(lastSlotCenter - tp20.width / 2, size.height - labelHeight + 4),
    );
  }

  @override
  bool shouldRepaint(_HistogramPainter old) =>
      old.buckets != buckets ||
      old.myBucket != myBucket ||
      old.myBarColor != myBarColor ||
      old.barColor != barColor ||
      old.labelColor != labelColor;
}
