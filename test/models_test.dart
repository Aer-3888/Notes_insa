import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/models.dart';

void main() {
  group('GradeUtils.parseDouble', () {
    test('parses plain numbers and fractions', () {
      expect(GradeUtils.parseDouble('15'), 15);
      expect(GradeUtils.parseDouble('15/20'), 15);
    });

    test('handles comma decimals', () {
      expect(GradeUtils.parseDouble('15,5/20'), 15.5);
    });

    test('parses comma decimal coefficients', () {
      expect(GradeInstance('a', 10, coeff: '1,5').coeffValue, 1.5);
    });

    test('returns null for absence markers (case-insensitive) and null', () {
      expect(GradeUtils.parseDouble('ABS'), isNull);
      expect(GradeUtils.parseDouble('abs'), isNull);
      expect(GradeUtils.parseDouble('ABI'), isNull);
      expect(GradeUtils.parseDouble('Aucune note'), isNull);
      expect(GradeUtils.parseDouble(null), isNull);
    });
  });

  group('SubjectAverage.fromJson', () {
    test('parses a full row', () {
      final a = SubjectAverage.fromJson({
        'ue_name': 'UE1',
        'subject_name': 'Math',
        'avg': 12.5,
        'min': 2,
        'max': 18,
        'count': 30,
      });
      expect(a.ueName, 'UE1');
      expect(a.subjectName, 'Math');
      expect(a.avg, 12.5);
      expect(a.count, 30);
    });

    test('tolerates missing/null fields without throwing', () {
      final a = SubjectAverage.fromJson({'ue_name': null});
      expect(a.ueName, '');
      expect(a.subjectName, '');
      expect(a.avg, 0);
      expect(a.count, 0);
    });
  });

  group('averages math', () {
    test('Subject unweighted average', () {
      final s = Subject(
        'S',
        1.0,
        {},
        grades: [GradeInstance('a', 10), GradeInstance('b', 14)],
      );
      expect(s.average, 12);
      expect(s.isAverageEstimated, isTrue);
    });

    test('Subject prefers extracted average over grade estimate', () {
      final s = Subject(
        'S',
        1.0,
        {},
        grades: [GradeInstance('a', 10), GradeInstance('b', 14)],
        extractedAverage: 13,
      );
      expect(s.average, 13);
      expect(s.isAverageEstimated, isFalse);
    });

    test('Subject average is null when there are no grades', () {
      expect(Subject('S', 1.0, {}).average, isNull);
    });

    test('TeachingUnit weights subjects by coefficient', () {
      final u = TeachingUnit('UE', [
        Subject('A', 2.0, {}, grades: [GradeInstance('x', 10)]),
        Subject('B', 1.0, {}, grades: [GradeInstance('x', 16)]),
      ]);
      // (10*2 + 16*1) / 3 = 12
      expect(u.average, closeTo(12, 1e-9));
      expect(u.isAverageEstimated, isTrue);
    });

    test('TeachingUnit prefers extracted average over subject estimate', () {
      final u = TeachingUnit('UE', [
        Subject('A', 1.0, {}, grades: [GradeInstance('x', 10)]),
      ], extractedAverage: 11);
      expect(u.average, 11);
      expect(u.isAverageEstimated, isFalse);
    });

    test('TeachingUnit average is null when total coeff is zero', () {
      expect(TeachingUnit('UE', const []).average, isNull);
    });

    test('isValidated passes at exactly 10', () {
      final u = TeachingUnit('UE', [
        Subject('A', 1.0, {}, grades: [GradeInstance('x', 10)]),
      ]);
      expect(u.isValidated, isTrue);
    });
  });
}
