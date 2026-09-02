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
    final gradeColor = GradeUtils.getColor(subject.average);
    final averagePrefix = subject.isAverageEstimated ? '≈' : '';
    final averageText = subject.average == null
        ? null
        : '$averagePrefix${subject.average!.toStringAsFixed(2)}';

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
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
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    averageText != null
                        ? Text(
                            'Ma note: $averageText',
                            style: TextStyle(
                              fontSize: 14,
                              color: gradeColor,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        : Text(
                            'Pas encore de note',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade500,
                            ),
                          ),
                  ],
                ),
              ),
              _CoeffPill(coeff: subject.coeff),
            ],
          ),
          const SizedBox(height: 20),
          // Histogram or placeholder
          if (avg == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Column(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 48,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Statistiques non disponibles',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Soyez le premier à partager vos notes !',
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                  ),
                ],
              ),
            )
          else
            SizedBox(
              height: 160,
              child: _GradeHistogram(
                buckets: avg!.buckets,
                myGrade: subject.average,
              ),
            ),
          const SizedBox(height: 20),
          // Stats row
          if (avg != null)
            Row(
              children: [
                _StatCell(label: 'Moy', value: avg!.avg.toStringAsFixed(2)),
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
                _StatCell(label: 'Élèves', value: avg!.count.toString()),
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
          Text(
            value,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 32, color: Colors.grey.shade200);
  }
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
    final myBucketColor = GradeUtils.getColor(myGrade);

    return CustomPaint(
      painter: _HistogramPainter(
        buckets: buckets,
        myBucket: myBucket,
        myBucketColor: myBucketColor,
      ),
      size: Size.infinite,
    );
  }
}

class _HistogramPainter extends CustomPainter {
  final List<int> buckets;
  final int? myBucket;
  final Color myBucketColor;

  _HistogramPainter({
    required this.buckets,
    required this.myBucket,
    required this.myBucketColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const labelHeight = 20.0;
    const barInset = 1.5; // gap between tick and bar edge

    final maxCount = buckets.fold<int>(0, (m, b) => b > m ? b : m);
    if (maxCount == 0) return;

    final n = buckets.length; // 20
    // Each bar occupies an equal slot; label centered under bar center
    final slotWidth = size.width / n;
    final barWidth = slotWidth - barInset * 2;

    final barPaint = Paint()..style = PaintingStyle.fill;
    final labelStyle = TextStyle(fontSize: 9, color: Colors.grey.shade500);
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
      barPaint.color = isMyBar ? myBucketColor : Colors.grey.shade300;

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
          markerPaint.color = myBucketColor;
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
          text: TextSpan(text: label, style: labelStyle),
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
      text: TextSpan(text: '20', style: labelStyle),
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
      old.myBucketColor != myBucketColor;
}
