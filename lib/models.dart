import 'package:flutter/material.dart';

// Utilities for parsing grade strings and mapping grades to colors
class GradeUtils {
  static double? parseDouble(String? rawValue) {
    if (rawValue == null ||
        rawValue.contains("Aucun") ||
        rawValue.contains("Abs")) {
      return null;
    }
    try {
      // Replace comma with dot and parse the numeric portion before '/'
      final clean = rawValue.split('/')[0].replaceAll(',', '.');
      return double.parse(clean);
    } catch (e) {
      return null;
    }
  }

  // Returns a color appropriate for the given grade
  static Color getColor(double? grade) {
    if (grade == null) return Colors.grey;
    if (grade >= 14) return Colors.green.shade700;
    if (grade >= 10) return Colors.blue.shade700;
    return Colors.orange.shade800;
  }
}

// Simple grade record (e.g. "DS 1h: 17/20")
class GradeInstance {
  final String label; // e.g. "DS 1h"
  final double value; // e.g. 17.0

  GradeInstance(this.label, this.value);
}

// Subject model, contains a list of grade instances
class Subject {
  final String name;
  final double coeff;
  final Map<String, String> jsonKeys;

  List<GradeInstance> grades = [];

  Subject(this.name, this.coeff, this.jsonKeys);

  // Average of the subject's grades, or null when none
  double? get average {
    if (grades.isEmpty) return null;
    double sum = grades.fold(0, (prev, curr) => prev + curr.value);
    return sum / grades.length;
  }
}

// Teaching unit containing multiple subjects
class TeachingUnit {
  final String name;
  final List<Subject> subjects;

  TeachingUnit(this.name, this.subjects);

  // Weighted average for the unit (based on subject coefficients)
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

// Profile model: a named collection of TeachingUnits
class Profile {
  final String name;
  final List<TeachingUnit> units;
  final bool isActive;

  Profile(this.name, {List<TeachingUnit>? units, this.isActive = false})
    : units = units ?? [];

  int get unitCount => units.length;
}

// Parser to flatten nested grade structures into a map
class JsonGradeParser {
  // Recursively collect name->score entries from nested json
  static Map<String, String> flattenGrades(Map<String, dynamic> json) {
    final Map<String, String> result = {};

    void traverse(dynamic node) {
      if (node is Map<String, dynamic>) {
        if (node['name'] != null && node['score'] != null) {
          result[node['name'] as String] = node['score'] as String;
        }

        if (node['details'] is List) {
          for (var child in node['details']) {
            traverse(child);
          }
        }
      } else if (node is List) {
        for (var item in node) {
          traverse(item);
        }
      }
    }

    traverse(json);
    return result;
  }
}
