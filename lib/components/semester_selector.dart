import 'package:flutter/material.dart';

class SemesterSelector extends StatelessWidget {
  final int selectedSemester;
  final List<int> availableSemesters;
  final Function(int) onSemesterChanged;

  const SemesterSelector({
    super.key,
    required this.selectedSemester,
    required this.availableSemesters,
    required this.onSemesterChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (availableSemesters.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: availableSemesters
              .map(
                (sem) => Expanded(child: _buildSemButton(sem, "Semestre $sem")),
              )
              .toList(),
        ),
      ),
    );
  }

  Widget _buildSemButton(int sem, String label) {
    bool isSelected = selectedSemester == sem;
    return GestureDetector(
      onTap: () => onSemesterChanged(sem),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.indigo : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey.shade600,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
