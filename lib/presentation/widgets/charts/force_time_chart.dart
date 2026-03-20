import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../theme/app_theme.dart';

/// Real-time scrolling force-time chart.
/// Shows the last [windowS] seconds of force data.
class ForceTimeChart extends StatelessWidget {
  final List<double> timeS;        // relative timestamps (s)
  final List<double> forceTotalN;
  final List<double>? forceLeftN;
  final List<double>? forceRightN;
  final double? bodyWeightN;       // horizontal reference line
  final double windowS;            // visible time window
  final bool showChannels;         // show L/R lines

  const ForceTimeChart({
    super.key,
    required this.timeS,
    required this.forceTotalN,
    this.forceLeftN,
    this.forceRightN,
    this.bodyWeightN,
    this.windowS = 5.0,
    this.showChannels = false,
  });

  @override
  Widget build(BuildContext context) {
    if (timeS.isEmpty) return _empty(context);

    final tEnd   = timeS.last;
    final tStart = tEnd - windowS;
    final maxF   = _visibleMax(tStart);

    // Build spot lists
    final totalSpots = _toSpots(timeS, forceTotalN, tStart);
    final leftSpots  = showChannels && forceLeftN != null
        ? _toSpots(timeS, forceLeftN!, tStart) : <FlSpot>[];
    final rightSpots = showChannels && forceRightN != null
        ? _toSpots(timeS, forceRightN!, tStart) : <FlSpot>[];

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: windowS,
        minY: 0,
        maxY: maxF,
        clipData: const FlClipData.all(),
        backgroundColor: context.col.background,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          horizontalInterval: maxF / 4,
          verticalInterval: 1.0,
          getDrawingHorizontalLine: (_) => FlLine(
              color: context.col.border, strokeWidth: 0.5),
          getDrawingVerticalLine: (_) => FlLine(
              color: context.col.border, strokeWidth: 0.5),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 48,
              interval: maxF / 4,
              getTitlesWidget: (val, meta) => Text(
                '${val.toInt()}',
                style: IXTextStyles.chartAxis,
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: 1.0,
              getTitlesWidget: (val, meta) => Text(
                '${val.toStringAsFixed(0)}s',
                style: IXTextStyles.chartAxis,
              ),
            ),
          ),
          topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        extraLinesData: bodyWeightN != null
            ? ExtraLinesData(horizontalLines: [
                HorizontalLine(
                  y: bodyWeightN!,
                  color: AppColors.warning.withOpacity(0.5),
                  strokeWidth: 1,
                  dashArray: [6, 4],
                  label: HorizontalLineLabel(
                    show: true,
                    alignment: Alignment.topRight,
                    style: IXTextStyles.chartAxis.copyWith(
                        color: AppColors.warning),
                    labelResolver: (line) => 'BW',
                  ),
                ),
              ])
            : null,
        lineBarsData: [
          // Total force (always shown)
          LineChartBarData(
            spots: totalSpots,
            isCurved: false,
            color: AppColors.forceTotal,
            barWidth: 2,
            isStrokeCapRound: false,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: AppColors.forceTotal.withOpacity(0.06),
            ),
          ),
          // Left platform
          if (leftSpots.isNotEmpty)
            LineChartBarData(
              spots: leftSpots,
              isCurved: false,
              color: AppColors.forceLeft,
              barWidth: 1.5,
              dotData: const FlDotData(show: false),
            ),
          // Right platform
          if (rightSpots.isNotEmpty)
            LineChartBarData(
              spots: rightSpots,
              isCurved: false,
              color: AppColors.forceRight,
              barWidth: 1.5,
              dotData: const FlDotData(show: false),
            ),
        ],
      ),
      duration: Duration.zero, // No animation for real-time
    );
  }

  List<FlSpot> _toSpots(
      List<double> t, List<double> f, double tStart) {
    final spots = <FlSpot>[];
    for (int i = 0; i < t.length && i < f.length; i++) {
      final relT = t[i] - tStart;
      if (relT >= -0.1) {
        spots.add(FlSpot(relT.clamp(0, windowS), f[i].clamp(0, 99999)));
      }
    }
    return spots;
  }

  double _visibleMax(double tStart) {
    double max = 100;
    for (int i = 0; i < timeS.length && i < forceTotalN.length; i++) {
      if (timeS[i] >= tStart && forceTotalN[i] > max) max = forceTotalN[i];
    }
    return (max * 1.15).ceilToDouble();
  }

  Widget _empty(BuildContext context) => Container(
    color: context.col.background,
    child: Center(
      child: Text(
        'Esperando señal...',
        style: IXTextStyles.metricLabel,
      ),
    ),
  );
}
