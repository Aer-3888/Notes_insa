import 'package:flutter/material.dart';

/// Utilities for parsing grade strings and mapping grades to colors.
class GradeUtils {
  static double? parseDouble(String? rawValue) {
    if (rawValue == null ||
        rawValue.contains('Aucun') ||
        rawValue.contains('Abs')) {
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
    if (grade >= 14) return Colors.green.shade700;
    if (grade >= 10) return Colors.blue.shade700;
    return Colors.orange.shade800;
  }
}

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
    final apostropheRegex = RegExp(r"['’]");
    if (apostropheRegex.hasMatch(word)) {
      final parts = word.split(apostropheRegex);
      final matches = apostropheRegex.allMatches(word).toList();
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

  final parts = input.trim().split(RegExp(r"\s+"));
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

  List<GradeInstance> grades = [];

  Subject(this.name, this.coeff, this.jsonKeys);

  double? get average {
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

  TeachingUnit(this.name, this.subjects);

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

  /// A unit is validated when all subjects have an average and the weighted
  /// average is strictly greater than 10.
  bool get isValidated {
    if (subjects.isEmpty) return false;
    final allHaveAverage = subjects.every((s) => s.average != null);
    final avg = average;
    return allHaveAverage && (avg != null && avg > 10.0);
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

class JsonGradeParser {
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
