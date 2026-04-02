import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../theme/app_theme.dart';

/// Small colored badge showing a status (connected / disconnected / calibrated).
class StatusBadge extends StatelessWidget {
  final String label;
  final bool isOk;
  final IconData? icon;

  const StatusBadge({
    super.key,
    required this.label,
    required this.isOk,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final color = isOk ? AppColors.success : AppColors.danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7, height: 7,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
              letterSpacing: 0.5,
            ),
          ),
          if (icon != null) ...[
            const SizedBox(width: 4),
            Icon(icon, size: 12, color: color),
          ],
        ],
      ),
    );
  }
}

/// Phase indicator row (settling → descent → flight → landed).
/// For Drop Jump, pass [testType] = 'dropJump' to show DJ-specific phases.
class PhaseIndicatorRow extends StatelessWidget {
  final String currentPhase; // 'idle','settling','waiting','descent','flight','landed','djWaiting','djContact'
  final String? testType;

  const PhaseIndicatorRow({super.key, required this.currentPhase, this.testType});

  static const _defaultPhases = ['settling', 'descent', 'flight', 'landed'];
  static const _defaultLabels = ['Reposo', 'Descenso', 'Vuelo', 'Aterrizaje'];
  static const _djPhases = ['djWaiting', 'djContact', 'flight', 'landed'];
  static const _djLabels = ['Esperando', 'Contacto', 'Vuelo', 'Aterrizaje'];
  static const _activeColors = [
    AppColors.textDisabled,
    AppColors.info,
    AppColors.success,
    AppColors.warning,
  ];

  List<String> get _effectivePhases =>
      testType == 'dropJump' ? _djPhases : _defaultPhases;
  List<String> get _effectiveLabels =>
      testType == 'dropJump' ? _djLabels : _defaultLabels;

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    final phases = _effectivePhases;
    final labels = _effectiveLabels;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(phases.length, (i) {
        final isActive = currentPhase == phases[i] ||
            (currentPhase == 'waiting' && i == 0);
        final color = isActive ? _activeColors[i] : col.textDisabled;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Container(
                width: 10, height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive ? color : col.border,
                  boxShadow: isActive ? [
                    BoxShadow(color: color.withOpacity(0.5), blurRadius: 6),
                  ] : null,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                labels[i],
                style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
              if (i < phases.length - 1) ...[
                const SizedBox(width: 8),
                Icon(Icons.arrow_forward_ios, size: 8, color: col.border),
              ],
            ],
          ),
        );
      }),
    );
  }
}
