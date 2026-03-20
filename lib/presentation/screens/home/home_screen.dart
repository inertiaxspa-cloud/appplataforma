import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../domain/entities/athlete.dart';
import '../../../domain/entities/test_result.dart';
import '../../providers/connection_provider.dart';
import '../../providers/calibration_provider.dart';
import '../../providers/athlete_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/status_badge.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connState    = ref.watch(connectionProvider);
    final calState     = ref.watch(calibrationProvider);
    final athleteState = ref.watch(selectedAthleteProvider);

    final isConnected  = connState.isConnected;
    final isCalibrated = calState.isCalibrated;
    final hasAthlete   = athleteState != null;
    final canTest      = isConnected && isCalibrated && hasAthlete;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(),
              const SizedBox(height: 28),
              Text('ESTADO', style: IXTextStyles.sectionHeader()),
              const SizedBox(height: 12),
              _StatusPanel(
                isConnected: isConnected,
                isCalibrated: isCalibrated,
                connectedPort: connState.connectedName,
              ),
              const SizedBox(height: 24),
              Text('ATLETA', style: IXTextStyles.sectionHeader()),
              const SizedBox(height: 12),
              _AthleteSelector(selected: athleteState),
              const SizedBox(height: 28),
              Text('TESTS RÁPIDOS', style: IXTextStyles.sectionHeader()),
              const SizedBox(height: 12),
              _TestGrid(canTest: canTest),
              const SizedBox(height: 24),
              if (isConnected)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.show_chart, size: 18),
                    label: const Text('Monitor en Tiempo Real'),
                    onPressed: () => context.push('/monitor'),
                  ),
                ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const _BottomNav(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final col = context.col;
    return Row(
      children: [
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: 'INERTIA',
                style: TextStyle(
                  fontSize: 26, fontWeight: FontWeight.w800,
                  color: col.textPrimary, letterSpacing: 2,
                ),
              ),
              const TextSpan(
                text: 'X',
                style: TextStyle(
                  fontSize: 26, fontWeight: FontWeight.w800,
                  color: AppColors.primary, letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        IconButton(
          icon: Icon(Icons.settings_outlined, color: col.textSecondary),
          onPressed: () => context.push('/settings'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _StatusPanel extends StatelessWidget {
  final bool isConnected;
  final bool isCalibrated;
  final String? connectedPort;

  const _StatusPanel({
    required this.isConnected,
    required this.isCalibrated,
    this.connectedPort,
  });

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: col.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: col.border),
      ),
      child: Column(
        children: [
          _StatusRow(
            icon: Icons.usb,
            label: 'Plataforma',
            status: isConnected ? (connectedPort ?? 'Conectado') : 'Desconectado',
            isOk: isConnected,
            onTap: () => context.push('/connection'),
          ),
          Divider(height: 16, color: col.border),
          _StatusRow(
            icon: Icons.tune,
            label: 'Calibración',
            status: isCalibrated ? 'Calibrado' : 'Sin calibrar',
            isOk: isCalibrated,
            onTap: () => context.push('/calibration'),
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String status;
  final bool isOk;
  final VoidCallback onTap;

  const _StatusRow({
    required this.icon,
    required this.label,
    required this.status,
    required this.isOk,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 18, color: col.textSecondary),
            const SizedBox(width: 10),
            Text(label, style: TextStyle(fontSize: 14, color: col.textSecondary)),
            const Spacer(),
            StatusBadge(label: status, isOk: isOk),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 16, color: col.textDisabled),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _AthleteSelector extends ConsumerWidget {
  final Athlete? selected;
  const _AthleteSelector({this.selected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final col = context.col;
    if (selected == null) {
      return InkWell(
        onTap: () => context.push('/athletes'),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: col.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: AppColors.primary.withOpacity(0.3),
                width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withOpacity(0.1),
                ),
                child: const Icon(Icons.person_add_outlined,
                    color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              const Text('Seleccionar atleta',
                  style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w500)),
              const Spacer(),
              const Icon(Icons.chevron_right, color: AppColors.primary),
            ],
          ),
        ),
      );
    }

    return InkWell(
      onTap: () => context.push('/athletes'),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: col.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: col.border),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: AppColors.primary.withOpacity(0.15),
              child: Text(
                selected!.name.substring(0, 1).toUpperCase(),
                style: const TextStyle(
                    color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(selected!.name,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: col.textPrimary)),
                  if (selected!.sport != null)
                    Text(selected!.sport!,
                        style: TextStyle(fontSize: 12, color: col.textSecondary)),
                ],
              ),
            ),
            if (selected!.bodyWeightKg != null)
              Text(
                '${selected!.bodyWeightKg!.toStringAsFixed(1)} kg',
                style: TextStyle(fontSize: 13, color: col.textSecondary),
              ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, color: col.textDisabled),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _TestGrid extends StatelessWidget {
  final bool canTest;
  const _TestGrid({required this.canTest});

  static const _tests = [
    _TestItem('CMJ',        Icons.arrow_upward,   TestType.cmj,       '/tests/cmj',       AppColors.primary),
    _TestItem('Squat Jump', Icons.sports,          TestType.sj,        '/tests/sj',        AppColors.forceRight),
    _TestItem('Drop Jump',  Icons.download,        TestType.dropJump,  '/tests/dj',        AppColors.warning),
    _TestItem('Multi-Salto',Icons.repeat,          TestType.multiJump, '/tests/multijump', AppColors.secondary),
    _TestItem('Equilibrio', Icons.accessibility,   TestType.cop,       '/tests/cop',       AppColors.success),
    _TestItem('IMTP',       Icons.fitness_center,  TestType.imtp,      '/tests/imtp',      AppColors.danger),
  ];

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.0,
      ),
      itemCount: _tests.length,
      itemBuilder: (ctx, i) => _TestCard(
        item: _tests[i],
        enabled: canTest,
        onTap: canTest ? () => context.push(_tests[i].route) : null,
      ),
    );
  }
}

class _TestItem {
  final String label;
  final IconData icon;
  final TestType type;
  final String route;
  final Color color;
  const _TestItem(this.label, this.icon, this.type, this.route, this.color);
}

class _TestCard extends StatelessWidget {
  final _TestItem item;
  final bool enabled;
  final VoidCallback? onTap;

  const _TestCard({required this.item, required this.enabled, this.onTap});

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Opacity(
        opacity: enabled ? 1.0 : 0.4,
        child: Container(
          decoration: BoxDecoration(
            color: col.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: col.border),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: item.color.withOpacity(0.12),
                ),
                child: Icon(item.icon, color: item.color, size: 20),
              ),
              const SizedBox(height: 8),
              Text(
                item.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: col.textPrimary,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _BottomNav extends ConsumerWidget {
  const _BottomNav();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return BottomNavigationBar(
      currentIndex: 0,
      items: const [
        BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Inicio'),
        BottomNavigationBarItem(
            icon: Icon(Icons.people_outlined),
            activeIcon: Icon(Icons.people),
            label: 'Atletas'),
        BottomNavigationBarItem(
            icon: Icon(Icons.history_outlined),
            activeIcon: Icon(Icons.history),
            label: 'Historial'),
        BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label: 'Ajustes'),
      ],
      onTap: (idx) {
        switch (idx) {
          case 0: context.go('/');
          case 1: context.go('/athletes');
          case 2: context.go('/history');
          case 3: context.go('/settings');
        }
      },
    );
  }
}
