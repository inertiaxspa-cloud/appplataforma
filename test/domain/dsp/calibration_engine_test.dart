import 'package:flutter_test/flutter_test.dart';
import 'package:inertiax/domain/dsp/calibration_engine.dart';
import 'package:inertiax/domain/entities/calibration_data.dart';

void main() {
  group('CalibrationEngine.computeCellGains', () {
    test('10kg on ADC mean=100 produces positive gain', () {
      // weight = 10kg, total corrected = 4 cells each reading 25 (sum = 100)
      // gain = (10 * 9.81) / 100 = 0.981 N/ADC-count
      final readings = [
        CellRawReading(
          weightKg: 10.0,
          rawAML: 25.0,
          rawAMR: 25.0,
          rawASL: 25.0,
          rawASR: 25.0,
        ),
      ];
      final gains = CalibrationEngine.computeCellGains(readings, 4);
      expect(gains['A_ML'], isNotNull);
      expect(gains['A_ML']!, greaterThan(0.0));
      expect(gains['A_ML']!, closeTo(0.981, 0.001));
    });

    test('all four cells share the same gain value', () {
      final readings = [
        CellRawReading(
            weightKg: 20.0,
            rawAML: 50.0,
            rawAMR: 50.0,
            rawASL: 50.0,
            rawASR: 50.0),
      ];
      final gains = CalibrationEngine.computeCellGains(readings, 4);
      expect(gains['A_ML'], equals(gains['A_MR']));
      expect(gains['A_MR'], equals(gains['A_SL']));
      expect(gains['A_SL'], equals(gains['A_SR']));
    });

    test('empty readings returns empty map (no exception)', () {
      final gains = CalibrationEngine.computeCellGains([], 4);
      expect(gains, isEmpty);
    });

    test('reading with weightKg <= 0 is skipped; count=0 → gain=1.0 (default, no exception)', () {
      final readings = [
        CellRawReading(
            weightKg: 0.0,
            rawAML: 50.0,
            rawAMR: 50.0,
            rawASL: 50.0,
            rawASR: 50.0),
      ];
      // When all readings have weightKg <= 0, count stays 0 → gain = 1.0
      // gain = 1.0, which is > 0, so no exception is thrown.
      expect(() => CalibrationEngine.computeCellGains(readings, 4),
          returnsNormally);
    });

    test('reading with total corrected < 1 is skipped; falls back to gain=1.0', () {
      final readings = [
        CellRawReading(
            weightKg: 10.0,
            rawAML: 0.0,
            rawAMR: 0.0,
            rawASL: 0.0,
            rawASR: 0.0),
      ];
      // totalCorrected = 0 < 1 → skipped; count=0 → gain=1.0 (no exception)
      expect(() => CalibrationEngine.computeCellGains(readings, 4),
          returnsNormally);
      final gains = CalibrationEngine.computeCellGains(readings, 4);
      expect(gains['A_ML'], closeTo(1.0, 1e-9));
    });

    test('multiple calibration points: gain is averaged', () {
      // Point 1: 10kg, sum=100 → gain1 = 0.981
      // Point 2: 20kg, sum=200 → gain2 = 0.981
      // average = 0.981
      final readings = [
        CellRawReading(
            weightKg: 10.0,
            rawAML: 25.0,
            rawAMR: 25.0,
            rawASL: 25.0,
            rawASR: 25.0),
        CellRawReading(
            weightKg: 20.0,
            rawAML: 50.0,
            rawAMR: 50.0,
            rawASL: 50.0,
            rawASR: 50.0),
      ];
      final gains = CalibrationEngine.computeCellGains(readings, 4);
      expect(gains['A_ML']!, closeTo(0.981, 0.001));
    });
  });

  group('CalibrationEngine.polyfit', () {
    test('linear fit through two perfect points returns exact coefficients', () {
      // y = 2x + 1 → coefficients should be [2.0, 1.0]
      final x = [0.0, 1.0, 2.0, 3.0];
      final y = [1.0, 3.0, 5.0, 7.0];
      final coeffs = CalibrationEngine.polyfit(x, y, 1);
      expect(coeffs.length, equals(2));
      expect(coeffs[0], closeTo(2.0, 1e-9)); // slope
      expect(coeffs[1], closeTo(1.0, 1e-9)); // intercept
    });

    test('quadratic fit through perfect parabola', () {
      // y = x² → coeffs [1, 0, 0]
      final x = [0.0, 1.0, 2.0, 3.0, 4.0];
      final y = x.map((v) => v * v).toList();
      final coeffs = CalibrationEngine.polyfit(x, y, 2);
      expect(coeffs.length, equals(3));
      expect(coeffs[0], closeTo(1.0, 1e-6));  // x²
      expect(coeffs[1], closeTo(0.0, 1e-6));  // x
      expect(coeffs[2], closeTo(0.0, 1e-6));  // constant
    });
  });

  group('CalibrationEngine.buildSegments', () {
    test('two calibration points produce one segment', () {
      final points = [
        const CalibrationPoint(weightKg: 0.0, rawSum: 0.0),
        const CalibrationPoint(weightKg: 10.0, rawSum: 100.0),
      ];
      final segments = CalibrationEngine.buildSegments(points);
      expect(segments.length, equals(1));
      expect(segments.first.slope, closeTo(0.1, 1e-9));
      expect(segments.first.intercept, closeTo(0.0, 1e-9));
    });

    test('fewer than 2 points returns empty list', () {
      expect(CalibrationEngine.buildSegments([]), isEmpty);
      expect(
        CalibrationEngine.buildSegments([
          const CalibrationPoint(weightKg: 10.0, rawSum: 100.0),
        ]),
        isEmpty,
      );
    });
  });
}
