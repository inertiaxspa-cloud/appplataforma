import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/l10n/app_strings.dart';
import '../../theme/app_theme.dart';

// ── Test metadata model ─────────────────────────────────────────────────────

class _TestInfo {
  final String title;
  final String subtitle;
  final String description;
  final List<String> metrics;
  final List<String> protocol;
  final Color color;
  final IconData icon;

  const _TestInfo({
    required this.title,
    required this.subtitle,
    required this.description,
    required this.metrics,
    required this.protocol,
    required this.color,
    required this.icon,
  });
}

Map<String, _TestInfo> _buildInfos() => <String, _TestInfo>{
  'cmj': _TestInfo(
    title: 'CMJ',
    subtitle: AppStrings.get('info_cmj_subtitle'),
    description: AppStrings.get('cmj_description'),
    metrics: [
      AppStrings.get('cmj_metric_height'),
      AppStrings.get('cmj_metric_power'),
      AppStrings.get('cmj_metric_impulse'),
      AppStrings.get('cmj_metric_rfd'),
      AppStrings.get('cmj_metric_asymmetry'),
      AppStrings.get('cmj_metric_rsi'),
    ],
    protocol: [
      AppStrings.get('cmj_protocol_1'),
      AppStrings.get('cmj_protocol_2'),
      AppStrings.get('cmj_protocol_3'),
      AppStrings.get('cmj_protocol_4'),
    ],
    color: AppColors.primary,
    icon: Icons.arrow_upward_rounded,
  ),
  'sj': _TestInfo(
    title: 'SJ',
    subtitle: AppStrings.get('info_sj_subtitle'),
    description: AppStrings.get('sj_description'),
    metrics: [
      AppStrings.get('sj_metric_height'),
      AppStrings.get('sj_metric_power'),
      AppStrings.get('sj_metric_impulse'),
      AppStrings.get('sj_metric_deficit'),
      AppStrings.get('sj_metric_asymmetry'),
    ],
    protocol: [
      AppStrings.get('sj_protocol_1'),
      AppStrings.get('sj_protocol_2'),
      AppStrings.get('sj_protocol_3'),
      AppStrings.get('sj_protocol_4'),
    ],
    color: AppColors.forceRight,
    icon: Icons.sports_rounded,
  ),
  'dj': _TestInfo(
    title: 'Drop Jump',
    subtitle: AppStrings.get('info_dj_subtitle'),
    description: AppStrings.get('dj_description'),
    metrics: [
      AppStrings.get('dj_metric_rsi'),
      AppStrings.get('dj_metric_height'),
      AppStrings.get('dj_metric_contact'),
      AppStrings.get('dj_metric_power'),
      AppStrings.get('dj_metric_asymmetry'),
    ],
    protocol: [
      AppStrings.get('dj_protocol_1'),
      AppStrings.get('dj_protocol_2'),
      AppStrings.get('dj_protocol_3'),
      AppStrings.get('dj_protocol_4'),
    ],
    color: AppColors.warning,
    icon: Icons.download_rounded,
  ),
  'multijump': _TestInfo(
    title: 'Multi-Salto',
    subtitle: AppStrings.get('info_multijump_subtitle'),
    description: AppStrings.get('multijump_description'),
    metrics: [
      AppStrings.get('mj_metric_avg_height'),
      AppStrings.get('mj_metric_best_worst'),
      AppStrings.get('mj_metric_fatigue'),
      AppStrings.get('mj_metric_rsi'),
      AppStrings.get('mj_metric_cv'),
      AppStrings.get('mj_metric_asymmetry'),
    ],
    protocol: [
      AppStrings.get('mj_protocol_1'),
      AppStrings.get('mj_protocol_2'),
      AppStrings.get('mj_protocol_3'),
      AppStrings.get('mj_protocol_4'),
    ],
    color: AppColors.secondary,
    icon: Icons.repeat_rounded,
  ),
  'imtp': _TestInfo(
    title: 'IMTP',
    subtitle: AppStrings.get('info_imtp_subtitle'),
    description: AppStrings.get('imtp_description'),
    metrics: [
      AppStrings.get('imtp_metric_peak'),
      AppStrings.get('imtp_metric_rfd'),
      AppStrings.get('imtp_metric_impulse'),
      AppStrings.get('imtp_metric_asymmetry'),
      AppStrings.get('imtp_metric_ttp'),
    ],
    protocol: [
      AppStrings.get('imtp_protocol_1'),
      AppStrings.get('imtp_protocol_2'),
      AppStrings.get('imtp_protocol_3'),
      AppStrings.get('imtp_protocol_4'),
    ],
    color: AppColors.danger,
    icon: Icons.fitness_center_rounded,
  ),
  'cop': _TestInfo(
    title: 'CoP',
    subtitle: AppStrings.get('info_cop_subtitle'),
    description: AppStrings.get('cop_description'),
    metrics: [
      AppStrings.get('cop_metric_area'),
      AppStrings.get('cop_metric_velocity'),
      AppStrings.get('cop_metric_range'),
      AppStrings.get('cop_metric_freq'),
      AppStrings.get('cop_metric_asymmetry'),
    ],
    protocol: [
      AppStrings.get('cop_protocol_1'),
      AppStrings.get('cop_protocol_2'),
      AppStrings.get('cop_protocol_3'),
      AppStrings.get('cop_protocol_4'),
    ],
    color: AppColors.success,
    icon: Icons.accessibility_new_rounded,
  ),
};

// ── Screen ──────────────────────────────────────────────────────────────────

class TestInfoScreen extends StatelessWidget {
  final String testType;

  const TestInfoScreen({super.key, required this.testType});

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    final info = _buildInfos()[testType.toLowerCase()];

    if (info == null) {
      return Scaffold(
        appBar: AppBar(title: Text(AppStrings.get('test_information'))),
        body: Center(
          child: Text(
            '${AppStrings.get('info_test_not_found')} ($testType)',
            style: TextStyle(color: col.textSecondary),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: col.background,
      appBar: AppBar(
        backgroundColor: col.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: col.textSecondary),
          onPressed: () => context.pop(),
        ),
        title: Text(
          info.title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: col.textPrimary,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: info.color.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: info.color.withOpacity(0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: info.color.withOpacity(0.15),
                    ),
                    child: Icon(info.icon, color: info.color, size: 28),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    info.subtitle,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: col.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    info.description,
                    style: TextStyle(
                      fontSize: 14,
                      color: col.textSecondary,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            // Metrics section
            _SectionHeader(label: AppStrings.get('metrics_measured')),
            const SizedBox(height: 12),
            ...info.metrics.map(
              (m) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 5),
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: info.color,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        m,
                        style: TextStyle(
                          fontSize: 14,
                          color: col.textPrimary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),
            // Protocol section
            _SectionHeader(label: AppStrings.get('test_protocol')),
            const SizedBox(height: 12),
            ...info.protocol.asMap().entries.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: info.color.withOpacity(0.15),
                      ),
                      child: Center(
                        child: Text(
                          '${entry.key + 1}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: info.color,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        entry.value,
                        style: TextStyle(
                          fontSize: 14,
                          color: col.textPrimary,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            // Dismiss button
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => context.pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: info.color,
                  foregroundColor: Colors.black.withOpacity(0.85),
                  minimumSize: const Size(double.infinity, 52),
                  shape: const StadiumBorder(),
                ),
                child: Text(
                  AppStrings.get('info_understood'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: IXTextStyles.sectionHeader(),
    );
  }
}
