import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../theme/app_theme.dart';

/// Visual left/right symmetry bar.
/// Turns red when asymmetry > [warningThresholdPct] (default 10%).
class SymmetryGauge extends StatelessWidget {
  final double leftPercent;   // 0–100
  final String leftLabel;
  final String rightLabel;
  final bool isEstimated;     // true when using 1-platform mode
  final double warningThresholdPct;

  const SymmetryGauge({
    super.key,
    required this.leftPercent,
    this.leftLabel  = 'IZQ',
    this.rightLabel = 'DER',
    this.isEstimated = false,
    this.warningThresholdPct = 10.0,
  });

  double get rightPercent => 100 - leftPercent;
  bool get isAsymmetric => (leftPercent - 50).abs() > warningThresholdPct;

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('SIMETRÍA', style: IXTextStyles.sectionHeader()),
            if (isEstimated)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.warning.withOpacity(0.4)),
                ),
                child: Text(
                  'estimado (1 plataforma)',
                  style: TextStyle(fontSize: 10, color: AppColors.warning),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _PctLabel(label: leftLabel,  percent: leftPercent,  align: TextAlign.left,  color: AppColors.forceLeft),
            _PctLabel(label: rightLabel, percent: rightPercent, align: TextAlign.right, color: AppColors.forceRight),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 10,
            child: LayoutBuilder(builder: (ctx, constraints) {
              final leftWidth = constraints.maxWidth * (leftPercent / 100);
              return Stack(
                children: [
                  Container(
                    width: constraints.maxWidth,
                    color: AppColors.forceRight.withOpacity(0.25),
                  ),
                  Container(
                    width: leftWidth,
                    color: AppColors.forceLeft.withOpacity(0.7),
                  ),
                  Positioned(
                    left: constraints.maxWidth / 2 - 1,
                    top: 0, bottom: 0,
                    child: Container(width: 2, color: col.background.withOpacity(0.8)),
                  ),
                ],
              );
            }),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            'Asimetría: ${(leftPercent - 50).abs().toStringAsFixed(1)}%',
            style: TextStyle(
              fontSize: 11,
              color: isAsymmetric ? AppColors.danger : col.textDisabled,
              fontWeight: isAsymmetric ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
        if (isAsymmetric)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Center(
              child: Text(
                '⚠ Supera el límite recomendado de $warningThresholdPct%',
                style: const TextStyle(fontSize: 10, color: AppColors.danger),
              ),
            ),
          ),
      ],
    );
  }
}

class _PctLabel extends StatelessWidget {
  final String label;
  final double percent;
  final TextAlign align;
  final Color color;

  const _PctLabel({
    required this.label,
    required this.percent,
    required this.align,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          align == TextAlign.left ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      children: [
        Text(label, style: IXTextStyles.metricLabel),
        Text(
          '${percent.toStringAsFixed(1)}%',
          style: GoogleFonts.robotoMono(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}
