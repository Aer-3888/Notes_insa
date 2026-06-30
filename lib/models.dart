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

  /// Color for a unit or EC that accounts for its validation status when no
  /// numeric grade is available. With a grade it behaves like [getColor]
  /// (green, blue, orange by threshold). Without one, a validated item (VAL or
  /// VALCOMP) reads as passing (blue) rather than grey, and grey is kept only
  /// for items still in progress (no published status).
  static Color getColorForStatus(double? grade, String? status) {
    if (grade != null) return getColor(grade);
    final code = status?.toUpperCase();
    if (code == 'VAL' || code == 'VALCOMP') return AppColors.gradePassing;
    return Colors.grey;
  }
}

/// Coefficient-weighted average of [items]. [valueOf] returns each item's value
/// (items returning null are skipped); [weightOf] returns its weight. Returns
/// null when no item contributes (all null, or total weight is 0), so callers
/// get a clean "no average" signal. With every weight equal this is the plain
/// mean.
double? weightedAverage<T>(
  Iterable<T> items,
  double? Function(T) valueOf,
  double Function(T) weightOf,
) {
  double totalScore = 0;
  double totalWeight = 0;
  for (final item in items) {
    final value = valueOf(item);
    if (value == null) continue;
    final weight = weightOf(item);
    totalScore += value * weight;
    totalWeight += weight;
  }
  return totalWeight > 0 ? totalScore / totalWeight : null;
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

  double? get coeffValue =>
      coeff.isEmpty ? null : double.tryParse(coeff.replaceAll(',', '.'));
}

class Subject {
  final String name;
  final double coeff;
  final Map<String, String> jsonKeys;
  final List<GradeInstance> grades;
  final double? extractedAverage;

  /// Validation status from the grades payload, such as "VAL" or "VALCOMP".
  /// Null when the school has not published one, in which case no tag is shown.
  final String? extractedStatus;

  Subject(
    this.name,
    this.coeff,
    this.jsonKeys, {
    List<GradeInstance>? grades,
    this.extractedAverage,
    this.extractedStatus,
  }) : grades = grades ?? [];

  /// Official average from the grades payload, or a weighted estimate when the
  /// school has not provided the subject average yet.
  late final double? average = extractedAverage ?? _computeAverage();

  bool get isAverageEstimated => extractedAverage == null && average != null;

  // Weight each grade by its own coefficient, defaulting to 1.0 when absent —
  // so grades without coefficients collapse to a plain mean.
  double? _computeAverage() =>
      weightedAverage(grades, (g) => g.value, (g) => g.coeffValue ?? 1.0);
}

class TeachingUnit {
  final String name;
  final List<Subject> subjects;
  final double? extractedAverage;

  /// Validation status from the grades payload, such as "VAL" (validated),
  /// "VALCOMP" (validated by compensation), or "ADM". Null when the school has
  /// not published one yet, in which case the unit is still in progress.
  final String? extractedStatus;

  /// UE-level coefficient used to weight this unit in the semester average.
  /// Defaults to 1.0 when the coefficient is unknown.
  final double coeff;

  TeachingUnit(
    this.name,
    this.subjects, {
    this.coeff = 1.0,
    this.extractedAverage,
    this.extractedStatus,
  });

  /// The status shown on the unit card: the published code ("VAL", "VALCOMP",
  /// …) when available, otherwise "En cours".
  String get statusLabel => extractedStatus ?? 'En cours';

  /// Official average from the grades payload, or a weighted estimate when the
  /// school has not provided the UE average yet.
  late final double? average = extractedAverage ?? _computeAverage();

  bool get isAverageEstimated => extractedAverage == null && average != null;

  double? _computeAverage() =>
      weightedAverage(subjects, (s) => s.average, (s) => s.coeff);

  /// A unit is validated when all subjects have an average and the weighted
  /// average is at least 10 (10.00 is a pass). Cached on first access.
  late final bool isValidated = _computeIsValidated();

  bool _computeIsValidated() {
    if (subjects.isEmpty) return false;
    if (extractedAverage != null) return extractedAverage! >= 10.0;
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
