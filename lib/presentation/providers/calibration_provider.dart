import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/l10n/app_strings.dart';
import '../../data/datasources/local/database_helper.dart';
import '../../domain/dsp/calibration_engine.dart';
import '../../domain/entities/calibration_data.dart';

class CalibrationState {
  final CalibrationData? activeCalibration;
  final List<CalibrationPoint> pendingPoints;  // points added this session
  final bool isCalibrated;
  final bool isLoading;
  final String? error;

  const CalibrationState({
    this.activeCalibration,
    this.pendingPoints = const [],
    this.isCalibrated = false,
    this.isLoading = false,
    this.error,
  });

  CalibrationState copyWith({
    CalibrationData? activeCalibration,
    List<CalibrationPoint>? pendingPoints,
    bool? isCalibrated,
    bool? isLoading,
    String? error,
  }) => CalibrationState(
    activeCalibration: activeCalibration ?? this.activeCalibration,
    pendingPoints: pendingPoints ?? this.pendingPoints,
    isCalibrated: isCalibrated ?? this.isCalibrated,
    isLoading: isLoading ?? this.isLoading,
    error: error,
  );
}

class CalibrationNotifier extends StateNotifier<CalibrationState> {
  final DatabaseHelper _db;

  /// Per-cell tare offsets captured during the tare step.
  Map<String, double> _pendingOffsets = {};

  CalibrationNotifier(this._db) : super(const CalibrationState()) {
    _loadActive();
  }

  Future<void> _loadActive() async {
    state = state.copyWith(isLoading: true);
    try {
      final map = await _db.getActiveCalibration();
      if (map != null) {
        final cal = CalibrationData.fromMap(map);
        state = state.copyWith(
          activeCalibration: cal,
          isCalibrated: true,
          isLoading: false,
        );
      } else {
        state = state.copyWith(isLoading: false);
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Record the tare step: store per-cell offsets from zero-load raw readings.
  /// [rawAML/AMR/ASL/ASR] are the mean raw ADC values (negated) at zero load.
  void recordTare({
    required double rawAML,
    required double rawAMR,
    required double rawASL,
    required double rawASR,
  }) {
    _pendingOffsets = {
      'A_ML': rawAML,
      'A_MR': rawAMR,
      'A_SL': rawASL,
      'A_SR': rawASR,
    };
    // Also add the zero-weight calibration point (for backward compat)
    final rawSum = rawAML + rawAMR + rawASL + rawASR;
    final points = [
      ...state.pendingPoints,
      CalibrationPoint(
        weightKg: 0,
        rawSum: rawSum,
        rawAML: rawAML,
        rawAMR: rawAMR,
        rawASL: rawASL,
        rawASR: rawASR,
      ),
    ];
    state = state.copyWith(pendingPoints: points);
  }

  /// Add a calibration point with per-cell raw readings at a known weight.
  void addPoint(
    double weightKg,
    double rawSum, {
    double rawAML = 0,
    double rawAMR = 0,
    double rawASL = 0,
    double rawASR = 0,
  }) {
    final points = [
      ...state.pendingPoints,
      CalibrationPoint(
        weightKg: weightKg,
        rawSum: rawSum,
        rawAML: rawAML,
        rawAMR: rawAMR,
        rawASL: rawASL,
        rawASR: rawASR,
      ),
    ];
    state = state.copyWith(pendingPoints: points);
  }

  void removePoint(int index) {
    final points = [...state.pendingPoints]..removeAt(index);
    state = state.copyWith(pendingPoints: points);
  }

  /// Compute calibration from pending points and save.
  ///
  /// If per-cell offsets were recorded via [recordTare], the per-cell
  /// (offset+gain) approach is used. Otherwise falls back to polynomial.
  /// [cellPolarities] stores the polarity (+1/-1) per channel, embedded in
  /// the saved [CalibrationData] so [cellRawToNewton] applies it automatically.
  Future<void> computeAndSave({
    String name = 'Calibración',
    CalibrationMode mode = CalibrationMode.segmented,
    Map<String, double>? cellOffsets,
    Map<String, int>? cellPolarities,
  }) async {
    final points = state.pendingPoints;
    final weightPoints = points.where((p) => p.weightKg > 0).toList();
    if (weightPoints.length < 2) {
      state = state.copyWith(
          error: AppStrings.get('min_calibration_points'));
      return;
    }
    final uniqueWeights = weightPoints.map((p) => p.weightKg).toSet();
    if (uniqueWeights.length < 2) {
      state = state.copyWith(
          error: AppStrings.get('min_calibration_points'));
      return;
    }

    state = state.copyWith(isLoading: true, error: null);
    try {
      final offsets = cellOffsets ?? _pendingOffsets;
      final usePerCell = offsets.containsKey('A_ML');

      Map<String, double> cellGains = {};
      List<double> coeffs = [];
      List<LinearSegment> segments = [];

      if (usePerCell) {
        // Build CellRawReading list (subtract offsets for gain computation)
        final readings = <CellRawReading>[];
        for (final p in points) {
          if (p.weightKg <= 0) continue;
          readings.add(CellRawReading(
            weightKg: p.weightKg,
            rawAML: p.rawAML - (offsets['A_ML'] ?? 0),
            rawAMR: p.rawAMR - (offsets['A_MR'] ?? 0),
            rawASL: p.rawASL - (offsets['A_SL'] ?? 0),
            rawASR: p.rawASR - (offsets['A_SR'] ?? 0),
          ));
        }
        cellGains = CalibrationEngine.computeCellGains(readings, 1);
      } else {
        // Legacy polynomial
        final x = points.map((p) => p.rawSum).toList();
        final y = points.map((p) => p.weightKg).toList();

        if (mode == CalibrationMode.segmented) {
          segments = CalibrationEngine.buildSegments(points);
        } else {
          final degree = mode == CalibrationMode.linear ? 1
              : mode == CalibrationMode.quadratic ? 2 : 3;
          coeffs = CalibrationEngine.polyfit(x, y, degree);
        }
      }

      final cal = CalibrationData(
        name: name,
        mode: usePerCell ? CalibrationMode.linear : mode,
        coefficients: coeffs,
        segments: segments,
        cellOffsets: offsets.isNotEmpty
            ? offsets
            : {'A_L': 0, 'A_R': 0, 'B_L': 0, 'B_R': 0},
        cellGains: cellGains,
        cellPolarities: cellPolarities ?? {},
        points: points,
        isActive: true,
        createdAt: DateTime.now(),
      );

      final id = await _db.insertCalibration(cal.toMap());
      for (final p in points) {
        await _db.insertCalibrationPoint({
          'calibration_id': id,
          'weight_kg': p.weightKg,
          'raw_sum':   p.rawSum,
          'raw_aml':   p.rawAML,
          'raw_amr':   p.rawAMR,
          'raw_asl':   p.rawASL,
          'raw_asr':   p.rawASR,
        });
      }

      state = state.copyWith(
        activeCalibration: cal.copyWith(id: id),
        isCalibrated: true,
        pendingPoints: [],
        isLoading: false,
      );
      _pendingOffsets = {};
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void clearPendingPoints() {
    state = state.copyWith(pendingPoints: []);
    _pendingOffsets = {};
  }
}

extension _CalibrationDataCopyWith on CalibrationData {
  CalibrationData copyWith({int? id}) => CalibrationData(
    id: id ?? this.id,
    name: name,
    mode: mode,
    coefficients: coefficients,
    segments: segments,
    cellOffsets: cellOffsets,
    cellGains: cellGains,
    cellPolarities: cellPolarities,
    points: points,
    isActive: isActive,
    createdAt: createdAt,
  );
}

final calibrationProvider =
    StateNotifierProvider<CalibrationNotifier, CalibrationState>((ref) {
  return CalibrationNotifier(DatabaseHelper.instance);
});
