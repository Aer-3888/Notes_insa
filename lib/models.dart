import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Utilities for parsing grade strings and mapping grades to colors.
class GradeUtils {
  static double? parseDouble(String? rawValue) {
    if (rawValue == null) return null;
    // Non-numeric status markers carry no numeric grade and are excluded from
    // averages: "Aucun(e) note", "Abs" (absence), "ABI" (absence injustifiée).
    final lower = rawValue.toLowerCase();
    if (lower.contains('aucun') ||
        lower.contains('abs') ||
        lower.contains('abi')) {
      return null;
    }
    try {
      final clean = rawValue.split('/')[0].replaceAll(',', '.');
      return double.parse(clean);
    } catch (_) {
      return null;
    }
  }

  /// Returns a color appropriate for the given grade.
  static Color getColor(double? grade) {
    if (grade == null) return Colors.grey;
    if (grade >= 14) return AppColors.gradeExcellent;
    if (grade >= 10) return AppColors.gradePassing;
    return AppColors.gradeWarning;
  }
}

final RegExp _apostropheRegex = RegExp(r"['’]");
final RegExp _whitespaceRegex = RegExp(r'\s+');

/// Convert labels (often uppercase) to presentation-friendly Title Case.
/// Preserves common small French words in lowercase unless they are the first word.
String titleCase(String input) {
  if (input.isEmpty) return input;

  final smallWords = <String>{
    'de',
    'du',
    'des',
    'et',
    'pour',
    'la',
    'le',
    'les',
    'à',
    'au',
    'aux',
    'en',
    'sur',
    'chez',
    'dans',
    'par',
    'avec',
    'sans',
    'sous',
    'l',
    'd',
  };

  String titleSegment(String segment, bool isFirstSegment) {
    if (segment.isEmpty) return segment;
    final lower = segment.toLowerCase();
    if (!isFirstSegment && smallWords.contains(lower)) return lower;
    return lower[0].toUpperCase() +
        (lower.length > 1 ? lower.substring(1) : '');
  }

  String processWord(String word, bool isFirstWord) {
    if (_apostropheRegex.hasMatch(word)) {
      final parts = word.split(_apostropheRegex);
      final matches = _apostropheRegex.allMatches(word).toList();
      final processedParts = <String>[];

      for (var i = 0; i < parts.length; i++) {
        final part = parts[i];
        if (part.contains('-')) {
          final hyphenParts = part.split('-');
          final processedHyphens = hyphenParts
              .asMap()
              .entries
              .map((entry) {
                final si = entry.key;
                final seg = entry.value;
                return titleSegment(seg, isFirstWord && i == 0 && si == 0);
              })
              .join('-');
          processedParts.add(processedHyphens);
        } else {
          processedParts.add(titleSegment(part, isFirstWord && i == 0));
        }
      }

      for (var j = 1; j < parts.length; j++) {
        final prevRaw = parts[j - 1].toLowerCase();
        if (!isFirstWord && smallWords.contains(prevRaw)) {
          if (parts[j - 1].contains('-')) {
            final hyphenParts = parts[j - 1].split('-');
            processedParts[j - 1] = hyphenParts
                .map((hp) => hp.toLowerCase())
                .join('-');
          } else {
            processedParts[j - 1] = prevRaw;
          }
        }
      }

      var rebuilt = '';
      for (var i = 0; i < processedParts.length; i++) {
        rebuilt += processedParts[i];
        if (i < matches.length) rebuilt += "'";
      }
      return rebuilt;
    }

    if (word.contains('-')) {
      final parts = word.split('-');
      return parts
          .asMap()
          .entries
          .map((entry) {
            final si = entry.key;
            final seg = entry.value;
            return titleSegment(seg, isFirstWord && si == 0);
          })
          .join('-');
    }

    return titleSegment(word, isFirstWord);
  }

  final parts = input.trim().split(_whitespaceRegex);
  return parts
      .asMap()
      .entries
      .map((entry) {
        final i = entry.key;
        final word = entry.value;
        return processWord(word, i == 0);
      })
      .join(' ');
}

class SubjectAverage {
  final String ueName;
  final String subjectName;
  final double avg;
  final double min;
  final double max;
  final int count;
  final List<int> buckets; // length 20, index i = bucket [i, i+1)

  SubjectAverage({
    required this.ueName,
    required this.subjectName,
    required this.avg,
    required this.min,
    required this.max,
    required this.count,
    required this.buckets,
  });

  /// Approximate median: midpoint of the bucket where cumulative count
  /// first reaches or exceeds count / 2.
  double get median {
    final half = count / 2;
    int cumulative = 0;
    for (int i = 0; i < buckets.length; i++) {
      cumulative += buckets[i];
      if (cumulative >= half) {
        return i + 0.5;
      }
    }
    return avg; // fallback
  }

  factory SubjectAverage.fromJson(Map<String, dynamic> json) => SubjectAverage(
    ueName: (json['ue_name'] as String?) ?? '',
    subjectName: (json['subject_name'] as String?) ?? '',
    avg: (json['avg'] as num?)?.toDouble() ?? 0,
    min: (json['min'] as num?)?.toDouble() ?? 0,
    max: (json['max'] as num?)?.toDouble() ?? 0,
    count: (json['count'] as num?)?.toInt() ?? 0,
    buckets: List.generate(20, (i) => (json['b$i'] as num? ?? 0).toInt()),
  );
}

class GradeInstance {
  final String label;
  final double value;
  final String coeff;

  GradeInstance(this.label, this.value, {this.coeff = ''});

  double? get coeffValue => coeff.isEmpty ? null : double.tryParse(coeff);
}

class Subject {
  final String name;
  final double coeff;
  final Map<String, String> jsonKeys;
  final List<GradeInstance> grades;

  Subject(this.name, this.coeff, this.jsonKeys, {List<GradeInstance>? grades})
    : grades = grades ?? [];

  /// Computed once on first access and cached — Subjects are immutable after
  /// parsing, so the average never changes and is read many times per build.
  late final double? average = _computeAverage();

  double? _computeAverage() {
    if (grades.isEmpty) return null;
    final hasAnyCoeff = grades.any((g) => g.coeffValue != null);
    if (hasAnyCoeff) {
      double totalScore = 0;
      double totalCoeff = 0;
      for (final g in grades) {
        final c = g.coeffValue ?? 1.0;
        totalScore += g.value * c;
        totalCoeff += c;
      }
      if (totalCoeff == 0) return null;
      return totalScore / totalCoeff;
    }
    return grades.fold<double>(0, (prev, curr) => prev + curr.value) /
        grades.length;
  }
}

class TeachingUnit {
  final String name;
  final List<Subject> subjects;

  /// UE-level coefficient used to weight this unit in the semester average.
  /// Defaults to 1.0 when the coefficient is unknown.
  final double coeff;

  TeachingUnit(this.name, this.subjects, {this.coeff = 1.0});

  /// Computed once on first access and cached (see [Subject.average]).
  late final double? average = _computeAverage();

  double? _computeAverage() {
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

  /// A unit is validated when all subjects have an average and the weighted
  /// average is at least 10 (10.00 is a pass). Cached on first access.
  late final bool isValidated = _computeIsValidated();

  bool _computeIsValidated() {
    if (subjects.isEmpty) return false;
    final allHaveAverage = subjects.every((s) => s.average != null);
    return allHaveAverage && (average != null && average! >= 10.0);
  }
}

class Profile {
  final String name;
  final List<TeachingUnit> units;
  final bool isActive;

  Profile(this.name, {List<TeachingUnit>? units, this.isActive = false})
    : units = units ?? [];

  int get unitCount => units.length;
}

extension StringCleaning on String {
  static final RegExp _cleanNameRegex = RegExp(
    r'[\s\u00A0\u200B\u200D\uFEFF]+',
  );

  /// Aggressively clean a string by replacing all whitespace (including
  /// non-breaking spaces and hidden characters) with a single space and
  /// trimming it. This ensures consistent key matching between the
  /// curriculum parser and backend averages.
  String cleanName() {
    return replaceAll(_cleanNameRegex, ' ').trim();
  }
}
