import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../data/datasources/local/database_helper.dart';
import '../../../domain/entities/athlete.dart';
import '../../../domain/entities/test_result.dart';
import '../../providers/athlete_provider.dart';
import '../../theme/app_theme.dart';

// ── Provider ──────────────────────────────────────────────────────────────────

final _comparisonSessionsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, (int, String)>((ref, key) async {
  return DatabaseHelper.instance.getSessionsForAthleteAndType(key.$1, key.$2);
});

// ── Screen ────────────────────────────────────────────────────────────────────

class ComparisonScreen extends ConsumerStatefulWidget {
  final int? initialAthleteId;
  final TestType? initialTestType;

  const ComparisonScreen({
    super.key,
    this.initialAthleteId,
    this.initialTestType,
  });

  @override
  ConsumerState<ComparisonScreen> createState() => _ComparisonScreenState();
}

class _ComparisonScreenState extends ConsumerState<ComparisonScreen> {
  int? _athleteId;
  TestType _testType = TestType.cmj;

  @override
  void initState() {
    super.initState();
    _athleteId = widget.initialAthleteId;
    _testType = widget.initialTestType ?? TestType.cmj;
  }

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    final athletesAsync = ref.watch(athleteListProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.get('comparison_sessions')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/history'),
        ),
      ),
      body: Column(
        children: [
          // ── Filter bar ──────────────────────────────────────────────────────
          Container(
            color: col.surface,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppStrings.get('athlete_name'), style: TextStyle(fontSize: 11, color: col.textSecondary)),
                const SizedBox(height: 4),
                athletesAsync.when(
                  loading: () => const SizedBox(
                      height: 40, child: LinearProgressIndicator()),
                  error: (e, _) => Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: AppColors.danger),
                      const SizedBox(height: 12),
                      Text(AppStrings.get('error_loading'), style: const TextStyle(color: AppColors.danger)),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.refresh),
                        label: Text(AppStrings.get('retry')),
                        onPressed: () => ref.invalidate(athleteListProvider),
                      ),
                    ],
                  ),
                  data: (athletes) => _AthletePicker(
                    athletes: athletes,
                    selectedId: _athleteId,
                    onChanged: (id) => setState(() => _athleteId = id),
                  ),
                ),
                const SizedBox(height: 12),
                Text(AppStrings.get('test_type_label'),
                    style: TextStyle(fontSize: 11, color: col.textSecondary)),
                const SizedBox(height: 6),
                _TestTypeChips(
                  selected: _testType,
                  onChanged: (t) => setState(() => _testType = t),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: col.border),
          // ── Body ────────────────────────────────────────────────────────────
          Expanded(
            child: _athleteId == null
                ? _Placeholder(
                    icon: Icons.person_search,
                    message: AppStrings.get('select_athlete_compare'),
                  )
                : _ComparisonBody(
                    athleteId: _athleteId!,
                    testType: _testType,
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Athlete picker ────────────────────────────────────────────────────────────

class _AthletePicker extends StatelessWidget {
  final List<Athlete> athletes;
  final int? selectedId;
  final ValueChanged<int?> onChanged;

  const _AthletePicker({
    required this.athletes,
    required this.selectedId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    return DropdownButtonHideUnderline(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: col.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: col.border),
        ),
        child: DropdownButton<int?>(
          value: selectedId,
          isExpanded: true,
          hint: Text(AppStrings.get('select_athlete'),
              style: TextStyle(color: col.textSecondary, fontSize: 13)),
          dropdownColor: col.surface,
          style: TextStyle(color: col.textPrimary, fontSize: 13),
          icon: Icon(Icons.expand_more, color: col.textSecondary, size: 18),
          items: [
            DropdownMenuItem<int?>(
              value: null,
              child: Text(AppStrings.get('none_selected'),
                  style: TextStyle(color: col.textSecondary, fontSize: 13)),
            ),
            ...athletes.map((a) => DropdownMenuItem<int?>(
                  value: a.id,
                  child: Text(a.name),
                )),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// ── TestType chips ────────────────────────────────────────────────────────────

class _TestTypeChips extends StatelessWidget {
  final TestType selected;
  final ValueChanged<TestType> onChanged;

  const _TestTypeChips({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: TestType.values.map((t) {
          final isSel = t == selected;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text(t.displayName,
                  style: TextStyle(
                    fontSize: 11,
                    color: isSel ? AppColors.primary : AppColors.textSecondary,
                    fontWeight: isSel ? FontWeight.w600 : FontWeight.w400,
                  )),
              selected: isSel,
              onSelected: (_) => onChanged(t),
              selectedColor: AppColors.primary.withOpacity(0.15),
              backgroundColor: Colors.transparent,
              side: BorderSide(
                  color: isSel ? AppColors.primary : AppColors.border),
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Comparison body ───────────────────────────────────────────────────────────

class _ComparisonBody extends ConsumerWidget {
  final int athleteId;
  final TestType testType;

  const _ComparisonBody(
      {required this.athleteId, required this.testType});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async =
        ref.watch(_comparisonSessionsProvider((athleteId, testType.name)));

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
          child: Text('${AppStrings.get('error_loading')}: $e',
              style: const TextStyle(color: AppColors.danger))),
      data: (rows) {
        // Parse result JSON from each session row.
        final sessions = <_SessionEntry>[];
        for (final row in rows) {
          final json = row['result_json'] as String?;
          if (json == null) continue;
          try {
            final result = TestResult.fromJson(json);
            final dt =
                DateTime.tryParse(row['performed_at'] as String? ?? '') ??
                    DateTime.now();
            sessions.add(_SessionEntry(date: dt, result: result));
          } catch (e) { debugPrint('[Comparison] Parse error: $e'); }
        }

        if (sessions.isEmpty) {
          return _Placeholder(
            icon: Icons.bar_chart_outlined,
            message: AppStrings.get('no_sessions_yet'),
          );
        }

        if (sessions.length < 2) {
          return _Placeholder(
            icon: Icons.bar_chart,
            message: AppStrings.get('min_sessions'),
          );
        }

        // Cap at last 8 for readability.
        final shown = sessions.length > 8
            ? sessions.sublist(sessions.length - 8)
            : sessions;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (sessions.length > 8) ...[
              Text(
                '${AppStrings.get('showing_last_n')} ${sessions.length} ${AppStrings.get('sessions_word')}',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
            ],
            _MetricsTable(sessions: shown),
            const SizedBox(height: 20),
            _TrendChart(sessions: shown),
            const SizedBox(height: 20),
          ],
        );
      },
    );
  }
}

// ── Internal data class ───────────────────────────────────────────────────────

class _SessionEntry {
  final DateTime date;
  final TestResult result;
  const _SessionEntry({required this.date, required this.result});
}

// ── Trend chart ───────────────────────────────────────────────────────────────

class _TrendChart extends StatelessWidget {
  final List<_SessionEntry> sessions;
  const _TrendChart({required this.sessions});

  /// Returns (chartLabel, values, unit, lowerIsBetter) for the primary metric.
  (String, List<double>, String, bool) _primaryMetric() {
    final r = sessions.first.result;
    return switch (r) {
      DropJumpResult _ => (
          AppStrings.get('jump_height_short'),
          sessions.map((s) => (s.result as DropJumpResult).jumpHeightCm).toList(),
          'cm', false,
        ),
      JumpResult _ => (
          AppStrings.get('jump_height_short'),
          sessions.map((s) => (s.result as JumpResult).jumpHeightCm).toList(),
          'cm', false,
        ),
      MultiJumpResult _ => (
          AppStrings.get('mean_height_short'),
          sessions.map((s) => (s.result as MultiJumpResult).meanHeightCm).toList(),
          'cm', false,
        ),
      ImtpResult _ => (
          AppStrings.get('peak_force_short'),
          sessions.map((s) => (s.result as ImtpResult).peakForceN).toList(),
          'N', false,
        ),
      CoPResult _ => (
          AppStrings.get('ellipse_area_short'),
          sessions.map((s) => (s.result as CoPResult).areaEllipseMm2).toList(),
          'mm²', true,
        ),
      FreeTestResult _ => (
          AppStrings.get('peak_force_short'),
          sessions.map((s) => (s.result as FreeTestResult).peakForceN).toList(),
          'N', false,
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    final (label, values, unit, lowerIsBetter) = _primaryMetric();

    final spots = List.generate(
        values.length, (i) => FlSpot(i.toDouble(), values[i]));

    final minY = values.reduce((a, b) => a < b ? a : b);
    final maxY = values.reduce((a, b) => a > b ? a : b);
    final pad = (maxY - minY) * 0.20 + 1;

    final bestVal = lowerIsBetter
        ? values.reduce((a, b) => a < b ? a : b)
        : values.reduce((a, b) => a > b ? a : b);
    final bestIndex = values.indexOf(bestVal);

    return Container(
      decoration: BoxDecoration(
        color: col.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: col.border),
      ),
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Row(children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: col.textPrimary)),
              const Spacer(),
              Text(unit,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary)),
            ]),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 185,
            child: LineChart(
              LineChartData(
                minY: minY - pad,
                maxY: maxY + pad,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) =>
                      FlLine(color: col.border, strokeWidth: 0.5),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 46,
                      getTitlesWidget: (v, _) => Text(
                        _fmtAxis(v),
                        style: IXTextStyles.chartAxis,
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i < 0 || i >= sessions.length || v != i.toDouble()) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            DateFormat('d/M').format(sessions[i].date),
                            style: IXTextStyles.chartAxis,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.25,
                    color: AppColors.primary,
                    barWidth: 2,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, _, __, i) {
                        final isBest = i == bestIndex;
                        return FlDotCirclePainter(
                          radius: isBest ? 5.5 : 3.5,
                          color: isBest ? AppColors.success : AppColors.primary,
                          strokeWidth: 1.5,
                          strokeColor: col.background,
                        );
                      },
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primary.withOpacity(0.15),
                          AppColors.primary.withOpacity(0.0),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => col.surfaceHigh,
                    getTooltipItems: (touchedSpots) =>
                        touchedSpots.map((s) {
                          final i = s.x.toInt();
                          final date = i >= 0 && i < sessions.length
                              ? DateFormat('d MMM, HH:mm', AppStrings.currentLanguage)
                                  .format(sessions[i].date)
                              : '';
                          return LineTooltipItem(
                            '$date\n${s.y.toStringAsFixed(2)} $unit',
                            const TextStyle(
                                fontSize: 11,
                                color: AppColors.textPrimary,
                                height: 1.5),
                          );
                        }).toList(),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(
              '${lowerIsBetter ? AppStrings.get('best_min_label') : AppStrings.get('best_max_label')}: '
              '${bestVal.toStringAsFixed(2)} $unit  ·  '
              '${DateFormat("d MMM yyyy", AppStrings.currentLanguage).format(sessions[bestIndex].date)}',
              style: const TextStyle(
                  fontSize: 10, color: AppColors.success),
            ),
          ),
        ],
      ),
    );
  }

  String _fmtAxis(double v) {
    if (v.abs() >= 10000) return '${(v / 1000).toStringAsFixed(0)}k';
    if (v.abs() >= 100) return v.toStringAsFixed(0);
    return v.toStringAsFixed(1);
  }
}

// ── Metrics table ─────────────────────────────────────────────────────────────

class _MetricSpec {
  final String name;
  final String unit;
  final bool lowerIsBetter;
  final double Function(TestResult) extract;

  const _MetricSpec(this.name, this.unit, this.lowerIsBetter, this.extract);
}

class _MetricsTable extends StatelessWidget {
  final List<_SessionEntry> sessions;
  const _MetricsTable({required this.sessions});

  List<_MetricSpec> _specs() {
    final r = sessions.first.result;
    return switch (r) {
      DropJumpResult _ => _dropJumpSpecs(),
      JumpResult _     => _jumpSpecs(),
      MultiJumpResult _ => _multiJumpSpecs(),
      ImtpResult _     => _imtpSpecs(),
      CoPResult _      => _copSpecs(),
      FreeTestResult _ => _freeTestSpecs(),
    };
  }

  List<_MetricSpec> _jumpSpecs() => [
    _MetricSpec(AppStrings.get('jump_height_short'),       'cm',  false, (r) => (r as JumpResult).jumpHeightCm),
    _MetricSpec(AppStrings.get('flight_time_short'),       'ms',  false, (r) => (r as JumpResult).flightTimeMs),
    _MetricSpec(AppStrings.get('peak_force_short'),        'N',   false, (r) => (r as JumpResult).peakForceN),
    _MetricSpec(AppStrings.get('peak_power_short'),        'W',   false, (r) => (r as JumpResult).peakPowerImpulseW),
    _MetricSpec(AppStrings.get('propulsive_impulse_short'),'Ns',  false, (r) => (r as JumpResult).propulsiveImpulseNs),
    _MetricSpec(AppStrings.get('rfd_100ms_short'),         'N/s', false, (r) => (r as JumpResult).rfdAt100ms),
    _MetricSpec(AppStrings.get('time_to_peak_short'),      'ms',  true,  (r) => (r as JumpResult).timeToPeakForceMs),
    _MetricSpec(AppStrings.get('asymmetry_short'),         '%',   true,  (r) => (r as JumpResult).symmetry.asymmetryIndexPct),
  ];

  List<_MetricSpec> _dropJumpSpecs() => [
    ..._jumpSpecs(),
    _MetricSpec(AppStrings.get('contact_time_short'), 'ms', true,  (r) => (r as DropJumpResult).contactTimeMs),
    _MetricSpec(AppStrings.get('rsi_mod_short'),      '',   false, (r) => (r as DropJumpResult).rsiMod),
  ];

  List<_MetricSpec> _multiJumpSpecs() => [
    _MetricSpec(AppStrings.get('mean_height_short'),  'cm',  false, (r) => (r as MultiJumpResult).meanHeightCm),
    _MetricSpec(AppStrings.get('mean_contact_short'), 'ms',  true,  (r) => (r as MultiJumpResult).meanContactTimeMs),
    _MetricSpec(AppStrings.get('mean_rsi_short'),     '',    false, (r) => (r as MultiJumpResult).meanRsiMod),
    _MetricSpec(AppStrings.get('fatigue_short'),      '%',   true,  (r) => (r as MultiJumpResult).fatiguePercent),
    _MetricSpec(AppStrings.get('variability_short'),  '%',   true,  (r) => (r as MultiJumpResult).variabilityPercent),
    _MetricSpec(AppStrings.get('num_jumps_short'),    '',    false, (r) => (r as MultiJumpResult).jumpCount.toDouble()),
  ];

  List<_MetricSpec> _imtpSpecs() => [
    _MetricSpec(AppStrings.get('peak_force_short'),    'N',   false, (r) => (r as ImtpResult).peakForceN),
    _MetricSpec(AppStrings.get('peak_force_bw_short'), 'BW',  false, (r) => (r as ImtpResult).peakForceBW),
    _MetricSpec(AppStrings.get('net_impulse_short'),   'Ns',  false, (r) => (r as ImtpResult).netImpulseNs),
    _MetricSpec(AppStrings.get('rfd_50ms_short'),      'N/s', false, (r) => (r as ImtpResult).rfdAt50ms),
    _MetricSpec(AppStrings.get('rfd_100ms_short'),     'N/s', false, (r) => (r as ImtpResult).rfdAt100ms),
    _MetricSpec(AppStrings.get('time_to_peak_short'),  'ms',  true,  (r) => (r as ImtpResult).timeToPeakForceMs),
    _MetricSpec(AppStrings.get('asymmetry_short'),     '%',   true,  (r) => (r as ImtpResult).symmetry.asymmetryIndexPct),
  ];

  List<_MetricSpec> _copSpecs() => [
    _MetricSpec(AppStrings.get('ellipse_area_short'),   'mm²',  true,  (r) => (r as CoPResult).areaEllipseMm2),
    _MetricSpec(AppStrings.get('path_length_short'),    'mm',   true,  (r) => (r as CoPResult).pathLengthMm),
    _MetricSpec(AppStrings.get('mean_velocity_short'),  'mm/s', true,  (r) => (r as CoPResult).meanVelocityMmS),
    _MetricSpec(AppStrings.get('range_ml_short'),       'mm',   true,  (r) => (r as CoPResult).rangeMLMm),
    _MetricSpec(AppStrings.get('range_ap_short'),       'mm',   true,  (r) => (r as CoPResult).rangeAPMm),
    _MetricSpec(AppStrings.get('symmetry_short'),       '%',    false, (r) => (r as CoPResult).symmetryPercent),
  ];

  List<_MetricSpec> _freeTestSpecs() => [
    _MetricSpec(AppStrings.get('peak_force_short'),       'N',   false, (r) => (r as FreeTestResult).peakForceN),
    _MetricSpec(AppStrings.get('mean_force'),             'N',   false, (r) => (r as FreeTestResult).meanForceN),
    _MetricSpec(AppStrings.get('duration_label'),         's',   true,  (r) => (r as FreeTestResult).durationS),
    _MetricSpec(AppStrings.get('net_impulse_short'),      'N·s', false, (r) => (r as FreeTestResult).totalImpulseNs),
    _MetricSpec(AppStrings.get('peak_rfd'),               'N/s', false, (r) => (r as FreeTestResult).peakRfdNs),
  ];

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    final specs = _specs();

    // Column headers: short date per session.
    final headers = sessions
        .map((s) => DateFormat('d/M\nHH:mm').format(s.date))
        .toList();

    return Container(
      decoration: BoxDecoration(
        color: col.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: col.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Text(AppStrings.get('metrics_per_session'), style: IXTextStyles.sectionHeader()),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(AppStrings.get('best_label'),
                      style: TextStyle(
                          fontSize: 10, color: AppColors.success)),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: _buildTable(context, specs, headers),
          ),
        ],
      ),
    );
  }

  Widget _buildTable(BuildContext context,
      List<_MetricSpec> specs, List<String> headers) {
    final col = context.col;

    // Fixed column widths.
    const metricColW = 120.0;
    const dataColW   = 72.0;

    return Table(
      defaultColumnWidth: const FixedColumnWidth(dataColW),
      columnWidths: {
        0: const FixedColumnWidth(metricColW),
        for (int i = 1; i <= headers.length; i++)
          i: const FixedColumnWidth(dataColW),
      },
      border: TableBorder(
        horizontalInside:
            BorderSide(color: col.border.withOpacity(0.5), width: 0.5),
      ),
      children: [
        // Header row
        TableRow(
          decoration: BoxDecoration(color: col.background.withOpacity(0.4)),
          children: [
            _TCell(
              child: Text(AppStrings.get('metric_header'),
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary)),
            ),
            ...headers.map((h) => _TCell(
                  child: Text(h,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                          height: 1.4)),
                )),
          ],
        ),
        // Data rows
        ...specs.map((spec) {
          final values =
              sessions.map((s) => spec.extract(s.result)).toList();
          final bestVal = spec.lowerIsBetter
              ? values.reduce((a, b) => a < b ? a : b)
              : values.reduce((a, b) => a > b ? a : b);

          return TableRow(
            children: [
              // Metric label
              _TCell(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(spec.name,
                        style: TextStyle(
                            fontSize: 11, color: col.textPrimary)),
                    if (spec.unit.isNotEmpty)
                      Text(spec.unit,
                          style: const TextStyle(
                              fontSize: 9,
                              color: AppColors.textSecondary)),
                  ],
                ),
              ),
              // Value per session
              ...values.map((v) {
                final isBest = (v - bestVal).abs() < 0.001;
                return _TCell(
                  child: Text(
                    _fmt(v),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          isBest ? FontWeight.w700 : FontWeight.w400,
                      color: isBest
                          ? AppColors.success
                          : col.textPrimary,
                    ),
                  ),
                );
              }),
            ],
          );
        }),
      ],
    );
  }

  String _fmt(double v) {
    if (v.abs() >= 10000) return v.toStringAsFixed(0);
    if (v.abs() >= 100) return v.toStringAsFixed(1);
    return v.toStringAsFixed(2);
  }
}

// Helper cell widget for the table.
class _TCell extends StatelessWidget {
  final Widget child;
  const _TCell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: child,
    );
  }
}

// ── Placeholder ───────────────────────────────────────────────────────────────

class _Placeholder extends StatelessWidget {
  final IconData icon;
  final String message;
  const _Placeholder({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: col.textSecondary.withOpacity(0.3)),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14,
                  color: col.textSecondary,
                  fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}
