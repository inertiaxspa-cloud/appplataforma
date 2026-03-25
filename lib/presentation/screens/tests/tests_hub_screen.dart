import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/l10n/app_strings.dart';
import '../../providers/connection_provider.dart';
import '../../providers/calibration_provider.dart';
import '../../providers/language_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/test_illustrations.dart';

/// Tab-level hub that lists available tests and navigates to each.
class TestsHubScreen extends ConsumerWidget {
  const TestsHubScreen({super.key});

  static List<_TestItem> _buildTests() => [
    _TestItem('CMJ', AppStrings.get('test_cmj'),
        const CmjPainter(), '/tests/cmj', AppColors.primary, 'cmj'),
    _TestItem('Squat Jump', AppStrings.get('test_sj'),
        const SjPainter(), '/tests/sj', AppColors.forceRight, 'sj'),
    _TestItem('Drop Jump', AppStrings.get('test_dj'),
        const DjPainter(), '/tests/dj', AppColors.warning, 'dj'),
    _TestItem('Multi-Salto', AppStrings.get('test_multijump'),
        const MultiJumpPainter(), '/tests/multijump', AppColors.secondary, 'multijump'),
    _TestItem('Equilibrio / CoP', AppStrings.get('test_cop'),
        const CopPainter(), '/tests/cop', AppColors.success, 'cop'),
    _TestItem('IMTP', AppStrings.get('test_imtp'),
        const ImtpPainter(), '/tests/imtp', AppColors.danger, 'imtp'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch language so the hub rebuilds when the language changes.
    ref.watch(languageProvider);

    final col = context.col;
    final isConnected = ref.watch(connectionProvider).isConnected;
    final isCalibrated = ref.watch(calibrationProvider).isCalibrated;
    final canTest = isConnected && isCalibrated;
    final tests = _buildTests();

    return Scaffold(
      backgroundColor: col.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: col.background,
              elevation: 0,
              title: Text(
                AppStrings.get('tests_section'),
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: col.textPrimary),
              ),
              centerTitle: false,
            ),
            if (!canTest)
              SliverToBoxAdapter(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.warningDim,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline,
                            color: AppColors.warning, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isConnected
                                ? AppStrings.get('calibrate_before_test')
                                : AppStrings.get('connect_before_test'),
                            style: TextStyle(
                                fontSize: 12, color: col.textPrimary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _TestRow(
                      item: tests[i],
                      enabled: canTest,
                      isConnected: isConnected,
                    ),
                  ),
                  childCount: tests.length,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TestItem {
  final String label;
  final String description;
  final CustomPainter painter;
  final String route;
  final Color color;
  final String infoKey;
  const _TestItem(
      this.label, this.description, this.painter, this.route, this.color,
      this.infoKey);
}

class _TestRow extends StatelessWidget {
  final _TestItem item;
  final bool enabled;
  final bool isConnected;
  const _TestRow({required this.item, required this.enabled, required this.isConnected});

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: InkWell(
        onTap: enabled
            ? () => context.push(item.route)
            : () {
                final msg = !isConnected
                    ? AppStrings.get('connect_platform_first')
                    : AppStrings.get('calibrate_platform_first');
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(msg),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 2),
                ));
              },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
          decoration: BoxDecoration(
            color: col.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: col.border.withOpacity(0.5), width: 0.5),
          ),
          child: Row(
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: item.color.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(6),
                child: CustomPaint(
                  size: const Size(68, 68),
                  painter: item.painter,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.label,
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: col.textPrimary)),
                    const SizedBox(height: 2),
                    Text(item.description,
                        style:
                            TextStyle(fontSize: 12, color: col.textSecondary)),
                  ],
                ),
              ),
              // Info button — always tappable regardless of connection state
              IconButton(
                tooltip: AppStrings.get('what_is_this_test'),
                icon: Icon(Icons.info_outline_rounded,
                    color: col.textDisabled, size: 20),
                onPressed: () =>
                    context.push('/test-info', extra: item.infoKey),
              ),
              Icon(Icons.chevron_right, color: col.textDisabled),
            ],
          ),
        ),
      ),
    );
  }
}
