import 'package:flutter/material.dart';
import '../models.dart';

class UnitCardGrid extends StatelessWidget {
  final List<TeachingUnit> curriculum;
  final Function(TeachingUnit) onUnitTap;

  const UnitCardGrid({
    super.key,
    required this.curriculum,
    required this.onUnitTap,
  });

  @override
  Widget build(BuildContext context) {
    if (curriculum.isEmpty) {
      return const Center(
        child: Text("Aucune donnée.", style: TextStyle(color: Colors.grey)),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.85,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: curriculum.length,
      itemBuilder: (context, index) {
        final unit = curriculum[index];
        final color = GradeUtils.getColor(unit.average);

        return GestureDetector(
          onTap: () => onUnitTap(unit),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Icon and Grade
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    CircleAvatar(
                      backgroundColor: color.withValues(alpha: .1),
                      child: Icon(Icons.school, color: color, size: 20),
                    ),
                    Text(
                      unit.average?.toStringAsFixed(2) ?? "-",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ],
                ),
                // Name
                Text(
                  unit.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                // Progress Bar
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      unit.average != null ? "Validé" : "En cours",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: (unit.average ?? 0) / 20,
                      backgroundColor: Colors.grey.shade100,
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
