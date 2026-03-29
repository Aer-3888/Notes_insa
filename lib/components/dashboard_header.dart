import 'package:flutter/material.dart';
import '../models.dart';
import '../app_colors.dart';

String _formatLastUpdated(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inSeconds < 60) return 'Mis à jour à l\'instant';
  if (diff.inMinutes < 60) return 'Mis à jour il y a ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'Mis à jour il y a ${diff.inHours} h';
  return 'Mis à jour il y a ${diff.inDays} j';
}

class DashboardHeader extends StatelessWidget {
  final double? average;
  final String title;
  final VoidCallback onMenuPressed;
  final DateTime? lastUpdated;
  final int selectedSemester;
  final List<int> availableSemesters;
  final ValueChanged<int> onSemesterChanged;

  const DashboardHeader({
    super.key,
    required this.average,
    required this.title,
    required this.onMenuPressed,
    this.lastUpdated,
    required this.selectedSemester,
    required this.availableSemesters,
    required this.onSemesterChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // Menu Button
              IconButton(
                icon: const Icon(Icons.menu, size: 28, color: Colors.black87),
                onPressed: onMenuPressed,
              ),
              const SizedBox(width: 8),

              // Department Title + last updated
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    if (lastUpdated != null)
                      Text(
                        _formatLastUpdated(lastUpdated!),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                  ],
                ),
              ),

              // Average Circle
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: GradeUtils.getColor(average),
                  boxShadow: [
                    BoxShadow(
                      color: GradeUtils.getColor(average).withValues(alpha: .4),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  average?.toStringAsFixed(2) ?? "-",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          if (availableSemesters.isNotEmpty) ...[
            const SizedBox(height: 12),
            _AnimatedSemesterSelector(
              availableSemesters: availableSemesters,
              selectedSemester: selectedSemester,
              onSemesterChanged: onSemesterChanged,
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _AnimatedSemesterSelector extends StatelessWidget {
  final List<int> availableSemesters;
  final int selectedSemester;
  final ValueChanged<int> onSemesterChanged;

  const _AnimatedSemesterSelector({
    required this.availableSemesters,
    required this.selectedSemester,
    required this.onSemesterChanged,
  });

  @override
  Widget build(BuildContext context) {
    final n = availableSemesters.length;
    final rawIdx = availableSemesters.indexOf(selectedSemester);
    final selectedIndex = rawIdx < 0 ? 0 : rawIdx;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.all(4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemWidth = constraints.maxWidth / n;

          return Stack(
            children: [
              // Pill animates independently — does not rebuild gesture detectors
              AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                left: selectedIndex * itemWidth,
                top: 0,
                bottom: 0,
                width: itemWidth,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              // Stable gesture detectors — never rebuilt during animation
              Row(
                children: List.generate(
                  n,
                  (i) => Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onSemesterChanged(availableSemesters[i]),
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic,
                          style: TextStyle(
                            color: i == selectedIndex
                                ? Colors.white
                                : Colors.grey.shade600,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          child: Text('Semestre ${availableSemesters[i]}'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
