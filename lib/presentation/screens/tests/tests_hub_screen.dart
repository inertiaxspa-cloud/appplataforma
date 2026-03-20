import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../providers/connection_provider.dart';
import '../../providers/calibration_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/test_illustrations.dart';

/// Tab-level hub that lists available tests and navigates to each.
class TestsHubScreen extends ConsumerWidget {
  const TestsHubScreen({super.key});

  static final _tests = [
    _TestItem('CMJ', 'Salto con Contramovimiento',
        const CmjPainter(), '/tests/cmj', AppColors.primary),
    _TestItem('Squat Jump', 'Salto sin Contramovimiento',
        const SjPainter(), '/tests/sj', AppColors.forceRight),
    _TestItem('Drop Jump', 'Caída y Rebote',
        const DjPainter(), '/tests/dj', AppColors.warning),
    _TestItem('Multi-Salto', 'Saltos Consecutivos con RSI',
        const MultiJumpPainter(), '/tests/multijump', AppColors.secondary),
    _TestItem('Equilibrio / CoP', 'Balance y Centro de Presión',
        const CopPainter(), '/tests/cop', AppColors.success),
    _TestItem('IMTP', 'Tracción Isométrica a Media Altura',
        const ImtpPainter(), '/tests/imtp', AppColors.danger),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final col = context.col;
    final isConnected = ref.watch(connectionProvider).isConnected;
    final isCalibrated = ref.watch(calibrationProvider).isCalibrated;
    final canTest = isConnected && isCalibrated;

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
                'Tests',
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
                                ? 'Calibra la plataforma antes de realizar tests.'
                                : 'Conecta la plataforma para realizar tests.',
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
                      item: _tests[i],
                      enabled: canTest,
                      isConnected: isConnected,
                    ),
                  ),
                  childCount: _tests.length,
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
  const _TestItem(
      this.label, this.description, this.painter, this.route, this.color);
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
                    ? 'Conecta la plataforma primero'
                    : 'Calibra la plataforma antes de hacer un test';
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(msg),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 2),
                ));
              },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
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
              Icon(Icons.chevron_right, color: col.textDisabled),
            ],
          ),
        ),
      ),
    );
  }
}
