import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/constants/app_colors.dart';
import '../../../domain/entities/test_result.dart';
import '../../theme/app_theme.dart';

/// Shown at the bottom of a test screen once the test completes.
/// Displays key metrics and provides "Ver resultado" / "Repetir" actions.
class PostTestPanel extends StatelessWidget {
  final TestResult result;
  final VoidCallback onViewResult;
  final VoidCallback onRepeat;

  const PostTestPanel({
    super.key,
    required this.result,
    required this.onViewResult,
    required this.onRepeat,
  });

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    return Container(
      color: col.surface,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Completion header
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle_outline,
                  color: AppColors.success, size: 20),
              const SizedBox(width: 8),
              Text(
                'Test completado',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.success,
                ),
              ),
            ],
          ).animate().fadeIn(duration: 300.ms),

          const SizedBox(height: 12),

          // Key metrics row
          _MetricsRow(result: result),

          const SizedBox(height: 16),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Repetir'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: col.textSecondary,
                    side: BorderSide(color: col.border),
                  ),
                  onPressed: onRepeat,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.bar_chart, size: 18),
                  label: const Text('Ver resultado completo'),
                  onPressed: onViewResult,
                ),
              ),
            ],
          ).animate().fadeIn(duration: 400.ms, delay: 100.ms),
        ],
      ),
    );
  }
}

// ── Key metrics 3-up ──────────────────────────────────────────────────────────

class _MetricsRow extends StatelessWidget {
  final TestResult result;
  const _MetricsRow({required this.result});

  @override
  Widget build(BuildContext context) {
    final items = _extractMetrics(result);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: items
          .map((m) => _MiniMetric(label: m.$1, value: m.$2, unit: m.$3))
          .toList(),
    );
  }

  List<(String, String, String)> _extractMetrics(TestResult r) {
    if (r is JumpResult) {
      return [
        ('ALTURA', r.jumpHeightCm.toStringAsFixed(1), 'cm'),
        ('VUELO', r.flightTimeMs.toStringAsFixed(0), 'ms'),
        ('F. PICO', r.peakForceN.toStringAsFixed(0), 'N'),
      ];
    } else if (r is DropJumpResult) {
      return [
        ('ALTURA', r.jumpHeightCm.toStringAsFixed(1), 'cm'),
        ('CONTACTO', r.contactTimeMs.toStringAsFixed(0), 'ms'),
        ('RSImod', r.rsiMod.toStringAsFixed(2), ''),
      ];
    } else if (r is MultiJumpResult) {
      return [
        ('SALTOS', r.jumpCount.toString(), ''),
        ('ALTURA M.', r.meanHeightCm.toStringAsFixed(1), 'cm'),
        ('RSI M.', r.meanRsiMod.toStringAsFixed(2), ''),
      ];
    } else if (r is ImtpResult) {
      return [
        ('F. PICO', r.peakForceN.toStringAsFixed(0), 'N'),
        ('F. PICO/PC', r.peakForceBW.toStringAsFixed(2), 'BW'),
        ('RFD 100ms', r.rfdAt100ms.toStringAsFixed(0), 'N/s'),
      ];
    } else if (r is CoPResult) {
      return [
        ('ÁREA', r.areaEllipseMm2.toStringAsFixed(0), 'mm²'),
        ('TRAY.', r.pathLengthMm.toStringAsFixed(0), 'mm'),
        ('SIM.', r.symmetryPercent.toStringAsFixed(1), '%'),
      ];
    }
    return [('—', '—', ''), ('—', '—', ''), ('—', '—', '')];
  }
}

class _MiniMetric extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  const _MiniMetric(
      {required this.label, required this.value, required this.unit});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: IXTextStyles.metricLabel.copyWith(fontSize: 10)),
        const SizedBox(height: 2),
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: value,
                style: IXTextStyles.metricValue(color: AppColors.primary)
                    .copyWith(fontSize: 22),
              ),
              if (unit.isNotEmpty)
                TextSpan(
                  text: ' $unit',
                  style: TextStyle(
                    fontSize: 11,
                    color: context.col.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
