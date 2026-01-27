import 'package:flutter/material.dart';

// Utilities for grade parsing and color coding
class GradeUtils {
  static double? parseDouble(String? rawValue) {
    if (rawValue == null ||
        rawValue.contains("Aucun") ||
        rawValue.contains("Abs"))
      return null;
    try {
      // Replaces comma with dot
      final clean = rawValue.split('/')[0].replaceAll(',', '.');
      return double.parse(clean);
    } catch (e) {
      return null;
    }
  }

  // Returns a color based on the grade
  static Color getColor(double? grade) {
    if (grade == null) return Colors.grey;
    if (grade >= 14) return Colors.green.shade700;
    if (grade >= 10) return Colors.blue.shade700;
    return Colors.orange.shade800;
  }
}

// 2. Grade model (e.g., "DS 1h: 17/20")
class GradeInstance {
  final String label; // e.g. "DS 1h"
  final double value; // e.g. 17.0

  GradeInstance(this.label, this.value);
}

// 3. Subject model (e.g. "Langage C")
class Subject {
  final String name;
  final double coeff;
  final Map<String, String> jsonKeys;

  // Grades listed for this subject
  List<GradeInstance> grades = [];

  Subject(this.name, this.coeff, this.jsonKeys);

  // Calculate average of all found sub-grades
  double? get average {
    if (grades.isEmpty) return null;
    double sum = grades.fold(0, (prev, curr) => prev + curr.value);
    return sum / grades.length;
  }
}

// 4. Teaching Unit (e.g. "UE Développement")
class TeachingUnit {
  final String name;
  final List<Subject> subjects;

  TeachingUnit(this.name, this.subjects);

  // Weighted Average for the whole UE
  double? get average {
    double totalScore = 0;
    double totalCoeff = 0;

    for (var sub in subjects) {
      if (sub.average != null) {
        totalScore += sub.average! * sub.coeff;
        totalCoeff += sub.coeff;
      }
    }

    if (totalCoeff == 0) return null;
    return totalScore / totalCoeff;
  }
}
