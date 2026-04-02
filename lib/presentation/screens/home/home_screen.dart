import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../domain/entities/athlete.dart';
import '../../../domain/entities/test_result.dart';
import '../../providers/connection_provider.dart';
import '../../providers/calibration_provider.dart';
import '../../providers/athlete_provider.dart';
import '../../providers/language_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/status_badge.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch language so the screen rebuilds when the language changes.
    ref.watch(languageProvider);

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
              Text(AppStrings.get('connect').toUpperCase(),
                  style: IXTextStyles.sectionHeader()),
              const SizedBox(height: 12),
              _StatusPanel(
                isConnected: isConnected,
                isCalibrated: isCalibrated,
                connectedPort: connState.connectedName,
              ),
              const SizedBox(height: 24),
              Text(AppStrings.get('athletes').toUpperCase(),
                  style: IXTextStyles.sectionHeader()),
              const SizedBox(height: 12),
              _AthleteSelector(selected: athleteState),
              const SizedBox(height: 28),
              Text(AppStrings.get('quick_tests').toUpperCase(), style: IXTextStyles.sectionHeader()),
              const SizedBox(height: 12),
              _TestGrid(canTest: canTest),
              const SizedBox(height: 24),
              if (isConnected)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.show_chart, size: 18),
                    label: Text(AppStrings.get('live_monitor')),
                    onPressed: () => context.push('/monitor'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final col = context.col;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        _IXLogo(isDark: isDark),
        const Spacer(),
        IconButton(
          icon: Icon(Icons.settings_outlined, color: col.textSecondary),
          onPressed: () => context.push('/settings'),
        ),
      ],
    );
  }
}

/// Logo InertiaX adaptado a cada tema.
/// Dark: invierte la imagen (negro→blanco) para visibilidad sobre fondo oscuro.
/// Light/Outdoor: usa la imagen original (negro sobre blanco).
class _IXLogo extends StatelessWidget {
  final bool isDark;
  const _IXLogo({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final img = Image.asset('assets/images/inertiax_logo.jpg', height: 32);
    if (!isDark) return img;
    // Invierte colores: negro→blanco, blanco→negro(≈fondo oscuro, casi invisible)
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix([
        -1,  0,  0, 0, 255,
         0, -1,  0, 0, 255,
         0,  0, -1, 0, 255,
         0,  0,  0, 1,   0,
      ]),
      child: img,
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

  /// Shorten a USB/serial port name for the status badge.
  /// "USB Serial Device (COM6)" → "COM6"
  /// "/dev/ttyUSB0" → "ttyUSB0"
  /// "InertiaX-A" → "InertiaX-A" (≤14 chars: keep as-is)
  static String _shortPortName(String name) {
    // Extract COM port number from Windows path
    final comMatch = RegExp(r'(COM\d+)').firstMatch(name);
    if (comMatch != null) return comMatch.group(1)!;
    // Extract device name from Unix path
    final devMatch = RegExp(r'/dev/(.+)$').firstMatch(name);
    if (devMatch != null) return devMatch.group(1)!;
    // Truncate anything longer than 14 characters
    if (name.length > 14) return '${name.substring(0, 12)}…';
    return name;
  }

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
            label: AppStrings.get('platform_section'),
            status: isConnected
                ? _shortPortName(connectedPort ?? AppStrings.get('connected'))
                : AppStrings.get('disconnected'),
            isOk: isConnected,
            onTap: () => context.push('/connection'),
          ),
          Divider(height: 16, color: col.border),
          _StatusRow(
            icon: Icons.tune,
            label: AppStrings.get('calibration_section'),
            subtitle: AppStrings.get('calibration_needed'),
            status: isCalibrated
                ? AppStrings.get('calibrated')
                : AppStrings.get('not_calibrated'),
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
  final String? subtitle;
  final String status;
  final bool isOk;
  final VoidCallback onTap;

  const _StatusRow({
    required this.icon,
    required this.label,
    required this.status,
    required this.isOk,
    required this.onTap,
    this.subtitle,
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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 14, color: col.textSecondary)),
                  if (subtitle != null)
                    Text(subtitle!,
                        style: TextStyle(fontSize: 11, color: col.textDisabled)),
                ],
              ),
            ),
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
              // TODO(i18n): add 'select_athlete' key for 'Seleccionar atleta' / 'Select athlete'
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
                selected!.name.isNotEmpty ? selected!.name[0].toUpperCase() : '?',
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

  static List<_TestItem> _buildTests() => [
    _TestItem('CMJ',         Icons.arrow_upward,   TestType.cmj,       '/tests/cmj',       AppColors.primary,    AppStrings.get('test_cmj')),
    _TestItem('Squat Jump',  Icons.sports,          TestType.sj,        '/tests/sj',        AppColors.forceRight, AppStrings.get('test_sj')),
    _TestItem('Drop Jump',   Icons.download,        TestType.dropJump,  '/tests/dj',        AppColors.warning,    AppStrings.get('test_dj')),
    _TestItem('Multi-Salto', Icons.repeat,          TestType.multiJump, '/tests/multijump', AppColors.secondary,  AppStrings.get('test_multijump')),
    _TestItem('Equilibrio',  Icons.accessibility,   TestType.cop,       '/tests/cop',       AppColors.success,    AppStrings.get('test_cop')),
    _TestItem('IMTP',        Icons.fitness_center,  TestType.imtp,      '/tests/imtp',      AppColors.danger,     AppStrings.get('test_imtp')),
  ];

  @override
  Widget build(BuildContext context) {
    final tests = _buildTests();
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.0,
      ),
      itemCount: tests.length,
      itemBuilder: (ctx, i) => _TestCard(
        item: tests[i],
        enabled: canTest,
        onTap: canTest ? () => context.push(tests[i].route) : null,
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
  final String subtitle;
  const _TestItem(this.label, this.icon, this.type, this.route, this.color, this.subtitle);
}

class _TestCard extends StatelessWidget {
  final _TestItem item;
  final bool enabled;
  final VoidCallback? onTap;

  const _TestCard({required this.item, required this.enabled, this.onTap});

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    return Tooltip(
      // TODO(i18n): add 'connect_platform_first' key
      message: enabled ? '' : 'Conecta la plataforma primero',
      child: InkWell(
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
                const SizedBox(height: 6),
                Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: col.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                ),
                const SizedBox(height: 2),
                Text(
                  item.subtitle,
                  style: TextStyle(
                    fontSize: 9,
                    color: col.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

