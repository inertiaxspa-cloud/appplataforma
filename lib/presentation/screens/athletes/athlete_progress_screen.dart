import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../data/datasources/local/database_helper.dart';
import '../../../domain/entities/athlete.dart';
import '../../../domain/entities/test_result.dart';
import '../../theme/app_theme.dart';

// ── Data model ────────────────────────────────────────────────────────────────

class _ProgressEntry {
  final DateTime date;
  final double mainValue;
  final double? symmetryPct;
  final TestResult result;

  const _ProgressEntry({
    required this.date,
    required this.mainValue,
    required this.symmetryPct,
    required this.result,
  });
}

// ── Providers ─────────────────────────────────────────────────────────────────

enum _TimeFilter {
  days30('30d', 30),
  days90('90d', 90),
  year1('1a', 365),
  all('Todo', null);

  final String label;
  final int? days;
  const _TimeFilter(this.label, this.days);
}

final _athleteProgressProvider =
    FutureProvider.family<List<_ProgressEntry>, ({int athleteId, TestType testType, _TimeFilter filter})>(
  (ref, params) async {
    if (params.athleteId < 0) return [];

    final rows = await DatabaseHelper.instance.getSessionsForAthleteAndType(
      params.athleteId,
      params.testType.name,
    );

    final cutoff = params.filter.days != null
        ? DateTime.now().subtract(Duration(days: params.filter.days!))
        : null;

    final entries = <_ProgressEntry>[];
    for (final row in rows) {
      final dateStr = row['performed_at'] as String? ?? '';
      final date = DateTime.tryParse(dateStr);
      if (date == null) continue;
      if (cutoff != null && date.isBefore(cutoff)) continue;

      final resultJson = row['result_json'] as String?;
      if (resultJson == null) continue;

      try {
        final result = TestResult.fromJson(resultJson);
        final main = _extractMainMetric(result);
        final sym = _extractSymmetry(result);
        if (main == null) continue;
        entries.add(_ProgressEntry(
          date: date,
          mainValue: main,
          symmetryPct: sym,
          result: result,
        ));
      } catch (e) {
        debugPrint('[Progress] Result parse error: $e');
        continue;
      }
    }

    // Already sorted ASC by DB query
    return entries;
  },
);

double? _extractMainMetric(TestResult r) {
  return switch (r) {
    DropJumpResult dr => dr.rsiMod,
    JumpResult jr     => jr.jumpHeightCm,
    MultiJumpResult m => m.meanRsiMod,
    ImtpResult i      => i.peakForceN / 1000.0,   // kN
    CoPResult c       => c.pathLengthMm,
  };
}

double? _extractSymmetry(TestResult r) {
  return switch (r) {
    DropJumpResult dr => dr.symmetry.asymmetryIndexPct,
    JumpResult jr     => jr.symmetry.asymmetryIndexPct,
    ImtpResult i      => i.symmetry.asymmetryIndexPct,
    _                 => null,
  };
}

String _metricLabel(TestType type) {
  return switch (type) {
    TestType.cmj || TestType.cmjArms || TestType.sj => AppStrings.get('metric_height_cm'),
    TestType.dropJump                               => AppStrings.get('metric_rsi_mod'),
    TestType.multiJump                              => AppStrings.get('metric_mean_rsi'),
    TestType.imtp                                   => AppStrings.get('metric_peak_force_kn'),
    TestType.cop                                    => AppStrings.get('metric_path_mm'),
  };
}

String _metricUnit(TestType type) {
  return switch (type) {
    TestType.cmj || TestType.cmjArms || TestType.sj => 'cm',
    TestType.dropJump || TestType.multiJump         => '',
    TestType.imtp                                   => 'kN',
    TestType.cop                                    => 'mm',
  };
}

// ── Screen ────────────────────────────────────────────────────────────────────

class AthleteProgressScreen extends ConsumerStatefulWidget {
  final Athlete athlete;
  const AthleteProgressScreen({super.key, required this.athlete});

  @override
  ConsumerState<AthleteProgressScreen> createState() =>
      _AthleteProgressScreenState();
}

class _AthleteProgressScreenState
    extends ConsumerState<AthleteProgressScreen> {
  TestType _selectedType = TestType.cmj;
  _TimeFilter _selectedFilter = _TimeFilter.all;

  static const _filterTypes = [
    TestType.cmj,
    TestType.sj,
    TestType.dropJump,
    TestType.imtp,
    TestType.cop,
  ];

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    final athlete = widget.athlete;
    final params = (
      athleteId: athlete.id ?? -1,
      testType: _selectedType,
      filter: _selectedFilter,
    );
    final progressAsync = ref.watch(_athleteProgressProvider(params));

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.get('progress')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/athletes'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: AppStrings.get('reload'),
            onPressed: () =>
                ref.invalidate(_athleteProgressProvider(params)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Header ──
          _AthleteHeader(athlete: athlete),
          const SizedBox(height: 16),

          // ── Test type selector ──
          _TestTypeChips(
            selected: _selectedType,
            types: _filterTypes,
            onSelected: (t) => setState(() => _selectedType = t),
          ),
          const SizedBox(height: 10),

          // ── Time filter ──
          _TimeFilterChips(
            selected: _selectedFilter,
            onSelected: (f) => setState(() => _selectedFilter = f),
          ),
          const SizedBox(height: 20),

          // ── Content depends on data ──
          progressAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            ),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  children: [
                    const Icon(Icons.error_outline,
                        color: AppColors.danger, size: 36),
                    const SizedBox(height: 8),
                    Text('${AppStrings.get('error_loading')} $e',
                        style: TextStyle(
                            color: col.textSecondary, fontSize: 13)),
                  ],
                ),
              ),
            ),
            data: (entries) {
              if (entries.isEmpty) {
                return _EmptyProgress(testType: _selectedType);
              }
              return _ProgressContent(
                entries: entries,
                testType: _selectedType,
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _AthleteHeader extends StatelessWidget {
  final Athlete athlete;
  const _AthleteHeader({required this.athlete});

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: col.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: col.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: AppColors.primary.withAlpha(38),
            child: Text(
              athlete.name.substring(0, 1).toUpperCase(),
              style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 22),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  athlete.name,
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: col.textPrimary),
                ),
                if (athlete.sport != null && athlete.sport!.isNotEmpty)
                  Text(athlete.sport!,
                      style: TextStyle(
                          fontSize: 13, color: col.textSecondary)),
              ],
            ),
          ),
          if (athlete.bodyWeightKg != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  athlete.bodyWeightKg!.toStringAsFixed(1),
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary),
                ),
                Text('kg',
                    style: TextStyle(
                        fontSize: 11, color: col.textSecondary)),
              ],
            ),
        ],
      ),
    );
  }
}

// ── Test type chips ───────────────────────────────────────────────────────────

class _TestTypeChips extends StatelessWidget {
  final TestType selected;
  final List<TestType> types;
  final ValueChanged<TestType> onSelected;
  const _TestTypeChips(
      {required this.selected,
      required this.types,
      required this.onSelected});

  String _label(TestType t) => switch (t) {
        TestType.cmj        => 'CMJ',
        TestType.cmjArms    => 'CMJ+',
        TestType.sj         => 'SJ',
        TestType.dropJump   => 'DJ',
        TestType.multiJump  => 'Multi',
        TestType.imtp       => 'IMTP',
        TestType.cop        => 'CoP',
      };

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: types.map((t) {
          final isSelected = t == selected;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(_label(t)),
              selected: isSelected,
              onSelected: (_) => onSelected(t),
              selectedColor: AppColors.primary.withAlpha(50),
              labelStyle: TextStyle(
                color: isSelected
                    ? AppColors.primary
                    : context.col.textSecondary,
                fontWeight:
                    isSelected ? FontWeight.w700 : FontWeight.normal,
                fontSize: 13,
              ),
              side: BorderSide(
                color:
                    isSelected ? AppColors.primary : context.col.border,
              ),
              backgroundColor: context.col.surface,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Time filter chips ─────────────────────────────────────────────────────────

class _TimeFilterChips extends StatelessWidget {
  final _TimeFilter selected;
  final ValueChanged<_TimeFilter> onSelected;
  const _TimeFilterChips(
      {required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: _TimeFilter.values.map((f) {
        final isSelected = f == selected;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(f.label),
            selected: isSelected,
            onSelected: (_) => onSelected(f),
            selectedColor: AppColors.secondary.withAlpha(50),
            labelStyle: TextStyle(
              color: isSelected
                  ? AppColors.secondary
                  : context.col.textSecondary,
              fontWeight:
                  isSelected ? FontWeight.w700 : FontWeight.normal,
              fontSize: 12,
            ),
            side: BorderSide(
              color:
                  isSelected ? AppColors.secondary : context.col.border,
            ),
            backgroundColor: context.col.surface,
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          ),
        );
      }).toList(),
    );
  }
}

// ── Main content (has data) ───────────────────────────────────────────────────

class _ProgressContent extends StatelessWidget {
  final List<_ProgressEntry> entries;
  final TestType testType;
  const _ProgressContent(
      {required this.entries, required this.testType});

  @override
  Widget build(BuildContext context) {
    final symmetryEntries =
        entries.where((e) => e.symmetryPct != null).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── KPI row ──
        _KpiRow(entries: entries, testType: testType),
        const SizedBox(height: 20),

        // ── Evolution chart ──
        _SectionLabel(label: '${AppStrings.get('progress_evolution')} — ${_metricLabel(testType).toUpperCase()}'),
        const SizedBox(height: 8),
        _EvolutionChart(entries: entries, testType: testType),
        const SizedBox(height: 20),

        // ── Symmetry chart ──
        if (symmetryEntries.length >= 2) ...[
          _SectionLabel(label: AppStrings.get('progress_asymmetry_index')),
          const SizedBox(height: 4),
          Text(
            AppStrings.get('progress_symmetry_hint'),
            style: TextStyle(
                fontSize: 11, color: context.col.textDisabled),
          ),
          const SizedBox(height: 8),
          _SymmetryChart(entries: symmetryEntries),
          const SizedBox(height: 20),
        ],

        // ── Box return analysis (DJ only) ──
        if (testType == TestType.dropJump)
          _BoxReturnAnalysis(entries: entries),

        // ── History table ──
        _SectionLabel(label: AppStrings.get('progress_recent_history')),
        const SizedBox(height: 8),
        _HistoryTable(entries: entries, testType: testType),
        const SizedBox(height: 32),
      ],
    );
  }
}

// ── KPI row ───────────────────────────────────────────────────────────────────

class _KpiRow extends StatelessWidget {
  final List<_ProgressEntry> entries;
  final TestType testType;
  const _KpiRow({required this.entries, required this.testType});

  @override
  Widget build(BuildContext context) {
    final values = entries.map((e) => e.mainValue).toList();
    final pr = values.reduce(math.max);
    final last = values.last;
    final last5 =
        values.length >= 5 ? values.sublist(values.length - 5) : values;
    final avg5 = last5.reduce((a, b) => a + b) / last5.length;
    final trend = last - avg5;
    final unit = _metricUnit(testType);

    return Row(
      children: [
        Expanded(
            child: _KpiCard(
                label: AppStrings.get('progress_best_pr'),
                value: _fmt(pr),
                unit: unit,
                color: const Color(0xFFFFD700))),
        const SizedBox(width: 8),
        Expanded(
            child: _KpiCard(
                label: AppStrings.get('progress_last'),
                value: _fmt(last),
                unit: unit,
                color: AppColors.primary)),
        const SizedBox(width: 8),
        Expanded(
            child: _KpiCard(
                label: AppStrings.get('progress_avg5'),
                value: _fmt(avg5),
                unit: unit,
                color: AppColors.secondary)),
        const SizedBox(width: 8),
        Expanded(
            child: _KpiCard(
                label: AppStrings.get('progress_trend'),
                value: '${trend >= 0 ? '+' : ''}${_fmt(trend)}',
                unit: unit,
                color: trend >= 0 ? AppColors.success : AppColors.danger,
                icon: trend >= 0
                    ? Icons.trending_up
                    : Icons.trending_down)),
      ],
    );
  }

  String _fmt(double v) {
    if (testType == TestType.imtp || testType == TestType.dropJump ||
        testType == TestType.multiJump) {
      return v.toStringAsFixed(2);
    }
    return v.toStringAsFixed(1);
  }
}

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color color;
  final IconData? icon;
  const _KpiCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: col.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: col.border),
      ),
      child: Column(
        children: [
          if (icon != null)
            Icon(icon, color: color, size: 16)
          else
            const SizedBox(height: 0),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: color),
            textAlign: TextAlign.center,
          ),
          if (unit.isNotEmpty)
            Text(unit,
                style: TextStyle(fontSize: 9, color: col.textDisabled)),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 9, color: col.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: context.col.textSecondary,
        letterSpacing: 1.8,
      ),
    );
  }
}

// ── Evolution chart ───────────────────────────────────────────────────────────

class _EvolutionChart extends StatefulWidget {
  final List<_ProgressEntry> entries;
  final TestType testType;
  const _EvolutionChart(
      {required this.entries, required this.testType});

  @override
  State<_EvolutionChart> createState() => _EvolutionChartState();
}

class _EvolutionChartState extends State<_EvolutionChart> {
  int? _touchedIndex;

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    final entries = widget.entries;
    if (entries.isEmpty) return const SizedBox.shrink();

    final values = entries.map((e) => e.mainValue).toList();
    final pr = values.reduce(math.max);
    final minVal = values.reduce(math.min);
    final maxVal = values.reduce(math.max);
    final range = (maxVal - minVal).abs();
    final yMin = (minVal - range * 0.15).clamp(0.0, double.infinity);
    final yMax = maxVal + range * 0.2;

    // Build spots
    final mainSpots = <FlSpot>[];
    for (int i = 0; i < entries.length; i++) {
      mainSpots.add(FlSpot(i.toDouble(), entries[i].mainValue));
    }

    // Moving average (window 3)
    final maSpots = <FlSpot>[];
    for (int i = 0; i < entries.length; i++) {
      final start = math.max(0, i - 1);
      final end = math.min(entries.length - 1, i + 1);
      final slice = values.sublist(start, end + 1);
      final avg = slice.reduce((a, b) => a + b) / slice.length;
      maSpots.add(FlSpot(i.toDouble(), avg));
    }

    return Container(
      height: 220,
      padding: const EdgeInsets.only(right: 12, top: 8, bottom: 4),
      decoration: BoxDecoration(
        color: col.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: col.border),
      ),
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (entries.length - 1).toDouble(),
          minY: yMin,
          maxY: yMax,
          clipData: const FlClipData.all(),
          backgroundColor: col.surface,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: range > 0 ? range / 4 : 1,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: col.border, strokeWidth: 0.5),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                interval: range > 0 ? range / 4 : 1,
                getTitlesWidget: (val, _) => Text(
                  _fmtY(val, widget.testType),
                  style: TextStyle(
                      fontSize: 9, color: col.textDisabled),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval:
                    entries.length > 8 ? (entries.length / 4).ceilToDouble() : 1,
                getTitlesWidget: (val, _) {
                  final idx = val.toInt();
                  if (idx < 0 || idx >= entries.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      DateFormat('d/M').format(entries[idx].date),
                      style: TextStyle(
                          fontSize: 9, color: col.textDisabled),
                    ),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
          ),
          lineTouchData: LineTouchData(
            touchCallback: (event, response) {
              if (response?.lineBarSpots != null &&
                  event is FlTapUpEvent) {
                setState(() {
                  _touchedIndex =
                      response?.lineBarSpots?.firstOrNull?.spotIndex ?? -1;
                });
              }
            },
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => col.surfaceHigh,
              getTooltipItems: (spots) => spots.map((s) {
                final idx = s.spotIndex;
                if (idx >= entries.length) return null;
                final e = entries[idx];
                final isPr = e.mainValue == pr;
                return LineTooltipItem(
                  '${DateFormat('d MMM', 'es').format(e.date)}\n'
                  '${_fmtY(s.y, widget.testType)} ${_metricUnit(widget.testType)}'
                  '${isPr ? '  PR' : ''}',
                  TextStyle(
                    color: isPr
                        ? const Color(0xFFFFD700)
                        : col.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                );
              }).toList(),
            ),
          ),
          lineBarsData: [
            // Main metric line
            LineChartBarData(
              spots: mainSpots,
              isCurved: true,
              curveSmoothness: 0.25,
              color: AppColors.primary,
              barWidth: 2.5,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, _, __, idx) {
                  final isPr = entries[idx].mainValue == pr;
                  final isTouched = idx == _touchedIndex;
                  return FlDotCirclePainter(
                    radius: isPr || isTouched ? 6 : 3.5,
                    color: isPr
                        ? const Color(0xFFFFD700)
                        : isTouched
                            ? AppColors.primary
                            : AppColors.primary.withAlpha(180),
                    strokeWidth: isPr ? 2 : 0,
                    strokeColor: isPr
                        ? const Color(0xFFFFD700).withAlpha(100)
                        : Colors.transparent,
                  );
                },
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary.withAlpha(40),
                    AppColors.primary.withAlpha(5),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
            // Moving average line
            LineChartBarData(
              spots: maSpots,
              isCurved: true,
              curveSmoothness: 0.4,
              color: AppColors.warning.withAlpha(160),
              barWidth: 1.5,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              dashArray: [6, 4],
            ),
          ],
        ),
        duration: const Duration(milliseconds: 300),
      ),
    );
  }

  String _fmtY(double v, TestType type) {
    if (type == TestType.imtp || type == TestType.dropJump ||
        type == TestType.multiJump) {
      return v.toStringAsFixed(2);
    }
    return v.toStringAsFixed(1);
  }
}

// ── Symmetry chart ────────────────────────────────────────────────────────────

class _SymmetryChart extends StatelessWidget {
  final List<_ProgressEntry> entries;
  const _SymmetryChart({required this.entries});

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    if (entries.isEmpty) return const SizedBox.shrink();

    final spots = <FlSpot>[];
    for (int i = 0; i < entries.length; i++) {
      final sym = entries[i].symmetryPct ?? 0;
      spots.add(FlSpot(i.toDouble(), sym));
    }

    return Container(
      height: 180,
      padding: const EdgeInsets.only(right: 12, top: 8, bottom: 4),
      decoration: BoxDecoration(
        color: col.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: col.border),
      ),
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (entries.length - 1).toDouble(),
          minY: 0,
          maxY: 30,
          clipData: const FlClipData.all(),
          backgroundColor: col.surface,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 5,
            getDrawingHorizontalLine: (val) {
              if (val == 10) {
                return FlLine(
                    color: AppColors.danger.withAlpha(120),
                    strokeWidth: 1,
                    dashArray: [6, 4]);
              }
              return FlLine(color: col.border, strokeWidth: 0.4);
            },
          ),
          borderData: FlBorderData(show: false),
          extraLinesData: ExtraLinesData(
            horizontalLines: [
              HorizontalLine(
                y: 10,
                color: AppColors.danger.withAlpha(160),
                strokeWidth: 1.5,
                dashArray: [6, 4],
                label: HorizontalLineLabel(
                  show: true,
                  alignment: Alignment.topRight,
                  padding:
                      const EdgeInsets.only(right: 4, bottom: 2),
                  style: const TextStyle(
                      fontSize: 9, color: AppColors.danger),
                  labelResolver: (_) => AppStrings.get('progress_limit_10'),
                ),
              ),
            ],
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 32,
                interval: 5,
                getTitlesWidget: (val, _) => Text(
                  '${val.toInt()}%',
                  style: TextStyle(
                      fontSize: 9, color: col.textDisabled),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: entries.length > 8
                    ? (entries.length / 4).ceilToDouble()
                    : 1,
                getTitlesWidget: (val, _) {
                  final idx = val.toInt();
                  if (idx < 0 || idx >= entries.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      DateFormat('d/M').format(entries[idx].date),
                      style: TextStyle(
                          fontSize: 9, color: col.textDisabled),
                    ),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => col.surfaceHigh,
              getTooltipItems: (spots) => spots.map((s) {
                final idx = s.spotIndex;
                if (idx >= entries.length) return null;
                final e = entries[idx];
                return LineTooltipItem(
                  '${DateFormat('d MMM', 'es').format(e.date)}\n'
                  '${s.y.toStringAsFixed(1)}% ${AppStrings.get('asymmetry_word')}',
                  TextStyle(
                      color: col.textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600),
                );
              }).toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.25,
              color: AppColors.secondary,
              barWidth: 2.5,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, _, __, ___) {
                  final bad = spot.y > 10;
                  return FlDotCirclePainter(
                    radius: 3.5,
                    color: bad ? AppColors.danger : AppColors.success,
                    strokeWidth: 0,
                    strokeColor: Colors.transparent,
                  );
                },
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [
                    AppColors.secondary.withAlpha(35),
                    AppColors.secondary.withAlpha(5),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 300),
      ),
    );
  }
}

// ── History table ─────────────────────────────────────────────────────────────

class _HistoryTable extends StatelessWidget {
  final List<_ProgressEntry> entries;
  final TestType testType;
  const _HistoryTable(
      {required this.entries, required this.testType});

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    final unit = _metricUnit(testType);

    // Last 10, most recent first
    final display =
        entries.reversed.take(10).toList();

    final values = entries.map((e) => e.mainValue).toList();
    final pr = values.isNotEmpty ? values.reduce(math.max) : 0.0;
    final avg5 = values.length >= 5
        ? values.sublist(values.length - 5).reduce((a, b) => a + b) / 5
        : (values.isNotEmpty
            ? values.reduce((a, b) => a + b) / values.length
            : 0.0);

    return Container(
      decoration: BoxDecoration(
        color: col.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: col.border),
      ),
      child: Column(
        children: [
          // Header row
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Expanded(
                    flex: 3,
                    child: Text(AppStrings.get('col_date'),
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: col.textSecondary,
                            letterSpacing: 1))),
                Expanded(
                    flex: 2,
                    child: Text(AppStrings.get('col_result'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: col.textSecondary,
                            letterSpacing: 1))),
                Expanded(
                    flex: 2,
                    child: Text(AppStrings.get('col_asymmetry'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: col.textSecondary,
                            letterSpacing: 1))),
                const SizedBox(width: 32),
              ],
            ),
          ),
          const Divider(height: 1),
          ...display.asMap().entries.map((me) {
            final i = me.key;
            final e = me.value;
            final isPr = e.mainValue == pr;
            final trend = _trendIndicator(e.mainValue, avg5);
            final isLast = i == display.length - 1;

            return Column(
              children: [
                InkWell(
                  onTap: () => context.push(
                    '/results/${e.result.sessionId ?? 'new'}',
                    extra: e.result,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    child: Row(
                      children: [
                        // Date
                        Expanded(
                          flex: 3,
                          child: Text(
                            DateFormat('d MMM yy', 'es')
                                .format(e.date),
                            style: TextStyle(
                                fontSize: 12, color: col.textPrimary),
                          ),
                        ),
                        // Value
                        Expanded(
                          flex: 2,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _fmtValue(e.mainValue),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: isPr
                                      ? const Color(0xFFFFD700)
                                      : col.textPrimary,
                                ),
                              ),
                              const SizedBox(width: 2),
                              Text(unit,
                                  style: TextStyle(
                                      fontSize: 9,
                                      color: col.textDisabled)),
                              if (isPr) ...[
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFD700)
                                        .withAlpha(30),
                                    borderRadius:
                                        BorderRadius.circular(4),
                                  ),
                                  child: const Text('PR',
                                      style: TextStyle(
                                          fontSize: 8,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFFFFD700))),
                                ),
                              ],
                            ],
                          ),
                        ),
                        // Symmetry
                        Expanded(
                          flex: 2,
                          child: e.symmetryPct != null
                              ? _SymmetryBadge(
                                  pct: e.symmetryPct!)
                              : Center(
                                  child: Text('—',
                                      style: TextStyle(
                                          color: col.textDisabled))),
                        ),
                        // Trend icon
                        SizedBox(
                          width: 32,
                          child: Icon(
                            trend.$1,
                            color: trend.$2,
                            size: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (!isLast)
                  Divider(height: 1, color: col.divider),
              ],
            );
          }),
        ],
      ),
    );
  }

  String _fmtValue(double v) {
    if (testType == TestType.imtp ||
        testType == TestType.dropJump ||
        testType == TestType.multiJump) {
      return v.toStringAsFixed(2);
    }
    return v.toStringAsFixed(1);
  }

  (IconData, Color) _trendIndicator(double value, double avg) {
    const threshold = 0.02; // 2% tolerance
    final diff = (value - avg) / avg.abs().clamp(0.001, double.infinity);
    if (diff > threshold) return (Icons.arrow_upward, AppColors.success);
    if (diff < -threshold) return (Icons.arrow_downward, AppColors.danger);
    return (Icons.remove, AppColors.warning);
  }
}

class _SymmetryBadge extends StatelessWidget {
  final double pct;
  const _SymmetryBadge({required this.pct});

  @override
  Widget build(BuildContext context) {
    final isGood = pct <= 10;
    final color = isGood ? AppColors.success : AppColors.danger;
    return Center(
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withAlpha(28),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          '${pct.toStringAsFixed(1)}%',
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color),
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyProgress extends StatelessWidget {
  final TestType testType;
  const _EmptyProgress({required this.testType});

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: col.textDisabled.withAlpha(20),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.bar_chart_rounded,
                size: 36, color: col.textDisabled),
          ),
          const SizedBox(height: 16),
          Text(
            'Sin tests de ${testType.displayName}',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: col.textSecondary),
          ),
          const SizedBox(height: 6),
          Text(
            AppStrings.get('progress_empty_hint'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: col.textDisabled),
          ),
        ],
      ),
    );
  }
}

// ── Box Return Analysis (DJ only) ────────────────────────────────────────────

class _BoxReturnAnalysis extends StatelessWidget {
  final List<_ProgressEntry> entries;
  const _BoxReturnAnalysis({required this.entries});

  @override
  Widget build(BuildContext context) {
    // Filter to box-return DJ results only
    final boxEntries = <({double heightCm, double contactMs, double rsi, DateTime date})>[];
    for (final e in entries) {
      if (e.result is DropJumpResult) {
        final dr = e.result as DropJumpResult;
        if (dr.isBoxReturn && dr.dropHeightCm > 0 && dr.contactTimeMs > 0) {
          boxEntries.add((
            heightCm: dr.dropHeightCm,
            contactMs: dr.contactTimeMs,
            rsi: dr.rsiMod,
            date: dr.computedAt,
          ));
        }
      }
    }
    if (boxEntries.isEmpty) return const SizedBox.shrink();

    // Group by height → best RSI per height
    final Map<double, ({double bestRsi, double bestContact})> byHeight = {};
    for (final e in boxEntries) {
      final existing = byHeight[e.heightCm];
      if (existing == null || e.rsi > existing.bestRsi) {
        byHeight[e.heightCm] = (bestRsi: e.rsi, bestContact: e.contactMs);
      }
    }
    final sortedHeights = byHeight.keys.toList()..sort();

    // Find optimal height (highest RSI reactive)
    double optimalHeight = sortedHeights.first;
    double optimalRsi = 0;
    for (final h in sortedHeights) {
      if (byHeight[h]!.bestRsi > optimalRsi) {
        optimalRsi = byHeight[h]!.bestRsi;
        optimalHeight = h;
      }
    }

    final col = context.col;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        _SectionLabel(label: AppStrings.get('height_vs_contact').toUpperCase()),
        const SizedBox(height: 4),
        Text(
          AppStrings.get('box_return_analysis_desc'),
          style: TextStyle(fontSize: 11, color: col.textDisabled),
        ),
        const SizedBox(height: 12),

        // Bar chart: height → contact time
        SizedBox(
          height: 180,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: boxEntries.map((e) => e.contactMs).reduce(math.max) * 1.2,
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: true, reservedSize: 40,
                    getTitlesWidget: (v, _) => Text('${v.toInt()}',
                        style: TextStyle(fontSize: 9, color: col.textDisabled))),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: true, reservedSize: 28,
                    getTitlesWidget: (v, _) {
                      final idx = v.toInt();
                      if (idx < 0 || idx >= sortedHeights.length) return const SizedBox.shrink();
                      return Text('${sortedHeights[idx].toInt()} cm',
                          style: TextStyle(fontSize: 10, color: col.textSecondary));
                    }),
                ),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              barGroups: sortedHeights.asMap().entries.map((e) {
                final h = e.value;
                final isOptimal = (h - optimalHeight).abs() < 0.1;
                return BarChartGroupData(x: e.key, barRods: [
                  BarChartRodData(
                    toY: byHeight[h]!.bestContact,
                    color: isOptimal ? AppColors.success : AppColors.primary,
                    width: 20,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                ]);
              }).toList(),
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Optimal badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.successDim,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.success.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.star, color: AppColors.success, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${AppStrings.get('optimal_height')}: ${optimalHeight.toInt()} cm  ·  '
                  'RSI ${optimalRsi.toStringAsFixed(2)}  ·  '
                  '${byHeight[optimalHeight]!.bestContact.toStringAsFixed(0)} ms',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                      color: AppColors.success),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Data table
        Table(
          columnWidths: const {
            0: FlexColumnWidth(1),
            1: FlexColumnWidth(1),
            2: FlexColumnWidth(1),
          },
          children: [
            TableRow(
              children: [
                _TableHeader(AppStrings.get('drop_height')),
                _TableHeader(AppStrings.get('contact_label_short')),
                _TableHeader(AppStrings.get('rsi_reactive')),
              ],
            ),
            ...sortedHeights.map((h) {
              final d = byHeight[h]!;
              final isOpt = (h - optimalHeight).abs() < 0.1;
              return TableRow(
                decoration: isOpt
                    ? BoxDecoration(color: AppColors.successDim)
                    : null,
                children: [
                  _TableCell('${h.toInt()} cm'),
                  _TableCell('${d.bestContact.toStringAsFixed(0)} ms'),
                  _TableCell(d.bestRsi.toStringAsFixed(2)),
                ],
              );
            }),
          ],
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

class _TableHeader extends StatelessWidget {
  final String text;
  const _TableHeader(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
    child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
        color: context.col.textSecondary)),
  );
}

class _TableCell extends StatelessWidget {
  final String text;
  const _TableCell(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
    child: Text(text, style: TextStyle(fontSize: 12, color: context.col.textPrimary)),
  );
}
