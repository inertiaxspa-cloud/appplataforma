import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../theme/app_theme.dart';

/// Displays a single metric: large value + label + optional unit/subtitle/delta.
///
/// Used in ResultDetailScreen and LiveMonitorScreen.
class MetricCard extends StatelessWidget {
  final String label;
  final String value;
  // Legacy parameter kept for backward compatibility — rendered as subtitle
  final String? unit;
  final String? subtitle;
  final String? delta;
  // Legacy parameter name (isDeltaPositive) and new (deltaPositive) both accepted
  final bool? deltaPositive;
  final bool isDeltaPositive;
  final Color? valueColor;
  // Legacy parameter kept for backward compatibility (ignored visually — replaced by gradient)
  final bool isHighlighted;
  final IconData? icon;

  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.subtitle,
    this.delta,
    this.deltaPositive,
    this.isDeltaPositive = true,
    this.valueColor,
    this.isHighlighted = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    // Resolve delta direction — prefer explicit deltaPositive, fallback to isDeltaPositive
    final bool resolvedDeltaPositive = deltaPositive ?? isDeltaPositive;
    // Prefer subtitle over unit if both provided
    final String? displaySubtitle = subtitle ?? unit;
    final Color resolvedValueColor = valueColor ?? AppColors.primary;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.surface, AppColors.surfaceHigh],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: Colors.white.withOpacity(0.06), width: 0.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Label row — optional icon
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Text(
                    label.toUpperCase(),
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Value
            Text(
              value,
              style: GoogleFonts.robotoMono(
                fontSize: 32,
                fontWeight: FontWeight.w600,
                color: resolvedValueColor,
                height: 1.0,
              ),
            ),
            if (displaySubtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                displaySubtitle,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            if (delta != null) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    resolvedDeltaPositive
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                    size: 12,
                    color: resolvedDeltaPositive
                        ? AppColors.success
                        : AppColors.danger,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    delta!,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: resolvedDeltaPositive
                          ? AppColors.success
                          : AppColors.danger,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(duration: const Duration(milliseconds: 300))
        .scaleXY(
            begin: 0.94,
            end: 1.0,
            curve: Curves.easeOutBack);
  }
}

/// Compact inline metric (for live monitor bar).
class CompactMetricTile extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color color;
  final String? subtitle;

  const CompactMetricTile({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    this.color = AppColors.primary,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: IXTextStyles.metricLabel),
        const SizedBox(height: 2),
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: value,
                style: GoogleFonts.robotoMono(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
              TextSpan(
                text: ' $unit',
                style: IXTextStyles.metricLabel
                    .copyWith(color: color.withOpacity(0.7)),
              ),
            ],
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            style: TextStyle(fontSize: 9, color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}
