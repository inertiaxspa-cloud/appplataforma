import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/l10n/app_strings.dart';
import '../../providers/live_data_provider.dart';
import '../../providers/connection_provider.dart';
import '../settings/settings_screen.dart';
import '../../theme/app_theme.dart';
import '../../widgets/cards/metric_card.dart';
import '../../widgets/cards/symmetry_gauge.dart';
import '../../widgets/charts/force_time_chart.dart';

/// Full-screen real-time force monitor.
/// Available whenever the device is connected, regardless of active test.
class LiveMonitorScreen extends ConsumerStatefulWidget {
  const LiveMonitorScreen({super.key});

  @override
  ConsumerState<LiveMonitorScreen> createState() => _LiveMonitorScreenState();
}

class _LiveMonitorScreenState extends ConsumerState<LiveMonitorScreen> {
  @override
  void initState() {
    super.initState();
    // Allow both portrait and landscape in this screen.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    // Restore portrait-only when leaving this screen.
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final live    = ref.watch(liveDataProvider);
    final conn    = ref.watch(connectionProvider);
    final showRaw = ref.watch(settingsProvider.select((s) => s.showRawData));

    final orientation = MediaQuery.of(context).orientation;
    final isLandscape = orientation == Orientation.landscape;

    if (isLandscape) {
      return _LandscapeLayout(
        live: live,
        conn: conn,
        showRaw: showRaw,
      );
    }

    // ── Portrait layout (original) ─────────────────────────────────────────
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.get('live_monitor')),
        actions: [
          if (showRaw)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withAlpha(30),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.warning.withAlpha(80)),
                  ),
                  child: Text('RAW',
                      style: GoogleFonts.robotoMono(
                          fontSize: 11,
                          color: AppColors.warning,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: context.col.surfaceHigh,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: context.col.border),
                ),
                child: Text(
                  '${live.platformCount} ${live.platformCount > 1 ? AppStrings.get('platforms_label').toLowerCase() : AppStrings.get('platform_section').toLowerCase()}',
                  style: IXTextStyles.metricLabel,
                ),
              ),
            ),
          ),
        ],
      ),
      body: conn.isConnected
          ? _MonitorBody(live: live, showRaw: showRaw)
          : _NotConnected(),
    );
  }
}

// ── Landscape layout ──────────────────────────────────────────────────────────

class _LandscapeLayout extends StatelessWidget {
  final LiveDataState live;
  final dynamic conn; // ConnectionState
  final bool showRaw;
  const _LandscapeLayout({
    required this.live,
    required this.conn,
    required this.showRaw,
  });

  @override
  Widget build(BuildContext context) {
    final col = context.col;

    return Scaffold(
      // No AppBar in landscape — maximise chart space.
      body: SafeArea(
        child: Stack(
          children: [
            if (!conn.isConnected)
              _NotConnected()
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── 60 %: Force-time chart ───────────────────────────────
                  Expanded(
                    flex: 6,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
                      child: Column(
                        children: [
                          Expanded(
                            child: ForceTimeChart(
                              timeS: live.timeS,
                              forceTotalN: live.forceTotalN,
                              forceLeftN: live.forceLeftN,
                              forceRightN: live.forceRightN,
                              showChannels: true,
                            ),
                          ),
                          if (showRaw) _RawDataPanel(live: live),
                        ],
                      ),
                    ),
                  ),

                  // ── 40 %: KPI panel ──────────────────────────────────────
                  Expanded(
                    flex: 4,
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(4, 8, 8, 8),
                      decoration: BoxDecoration(
                        color: col.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: col.border),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // Platform badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: col.surfaceHigh,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: col.border),
                            ),
                            child: Text(
                              '${live.platformCount} ${live.platformCount > 1 ? AppStrings.get('platforms_label').toLowerCase() : AppStrings.get('platform_section').toLowerCase()}',
                              style: IXTextStyles.metricLabel,
                            ),
                          ),
                          // Force metrics
                          CompactMetricTile(
                            label: AppStrings.get('total_force'),
                            value: live.currentForceN.toStringAsFixed(0),
                            unit: 'N',
                            color: AppColors.forceTotal,
                          ),
                          Container(
                              width: double.infinity,
                              height: 1,
                              color: col.border),
                          CompactMetricTile(
                            label: live.platformCount >= 2
                                ? AppStrings.get('left_platform')
                                : AppStrings.get('left_label'),
                            value: live.forceLeftN.isNotEmpty
                                ? live.forceLeftN.last.toStringAsFixed(0)
                                : '—',
                            unit: 'N',
                            color: AppColors.forceLeft,
                          ),
                          Container(
                              width: double.infinity,
                              height: 1,
                              color: col.border),
                          CompactMetricTile(
                            label: live.platformCount >= 2
                                ? AppStrings.get('right_platform')
                                : AppStrings.get('right_label'),
                            value: live.forceRightN.isNotEmpty
                                ? live.forceRightN.last.toStringAsFixed(0)
                                : '—',
                            unit: 'N',
                            color: AppColors.forceRight,
                          ),
                          // Symmetry gauge
                          SymmetryGauge(
                            leftPercent: live.leftPct,
                            leftLabel: live.platformCount >= 2 ? 'IZQ' : 'IZQ',
                            rightLabel: live.platformCount >= 2 ? 'DER' : 'DER',
                            isEstimated: live.platformCount == 1,
                          ),
                          // RAW chip
                          if (showRaw)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.warning.withAlpha(30),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: AppColors.warning.withAlpha(80)),
                              ),
                              child: Text('RAW',
                                  style: GoogleFonts.robotoMono(
                                      fontSize: 11,
                                      color: AppColors.warning,
                                      fontWeight: FontWeight.w700)),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

            // ── Back button (top-left corner) ────────────────────────────
            Positioned(
              top: 8,
              left: 8,
              child: Material(
                color: context.col.surfaceHigh.withAlpha(220),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(Icons.arrow_back,
                        size: 22, color: context.col.textPrimary),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Portrait body ─────────────────────────────────────────────────────────────

class _MonitorBody extends StatelessWidget {
  final LiveDataState live;
  final bool showRaw;
  const _MonitorBody({required this.live, required this.showRaw});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Force-time chart (fills available space) ──────────────────────
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: ForceTimeChart(
              timeS: live.timeS,
              forceTotalN: live.forceTotalN,
              forceLeftN: live.forceLeftN,
              forceRightN: live.forceRightN,
              showChannels: true,
            ),
          ),
        ),

        // ── Raw data panel (visible when showRawData = true) ──────────────
        if (showRaw) _RawDataPanel(live: live),

        // ── Bottom panel ──────────────────────────────────────────────────
        Container(
          color: context.col.surface,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Main metrics row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  CompactMetricTile(
                    label: AppStrings.get('total_force'),
                    value: live.currentForceN.toStringAsFixed(0),
                    unit: 'N',
                    color: AppColors.forceTotal,
                  ),
                  _Divider(),
                  CompactMetricTile(
                    label: live.platformCount >= 2 ? AppStrings.get('left_platform') : 'IZQUIERDA',
                    value: live.forceLeftN.isNotEmpty
                        ? live.forceLeftN.last.toStringAsFixed(0)
                        : '—',
                    unit: 'N',
                    color: AppColors.forceLeft,
                  ),
                  _Divider(),
                  CompactMetricTile(
                    label: live.platformCount >= 2 ? AppStrings.get('right_platform') : 'DERECHA',
                    value: live.forceRightN.isNotEmpty
                        ? live.forceRightN.last.toStringAsFixed(0)
                        : '—',
                    unit: 'N',
                    color: AppColors.forceRight,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Symmetry gauge
              SymmetryGauge(
                leftPercent: live.leftPct,
                leftLabel: live.platformCount >= 2 ? 'IZQ' : 'IZQ',
                rightLabel: live.platformCount >= 2 ? 'DER' : 'DER',
                isEstimated: live.platformCount == 1,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Raw data debug panel ───────────────────────────────────────────────────

class _RawDataPanel extends StatelessWidget {
  final LiveDataState live;
  const _RawDataPanel({required this.live});

  @override
  Widget build(BuildContext context) {
    final smoothed = live.currentSmoothedN;
    final raw      = live.currentForceN;
    final diff     = raw - smoothed;

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.warning.withAlpha(15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.warning.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('SEÑAL RAW',
              style: GoogleFonts.robotoMono(
                  fontSize: 10,
                  color: AppColors.warning,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1)),
          const SizedBox(height: 6),
          Row(
            children: [
              _RawCell('RAW', '${raw.toStringAsFixed(1)} N', AppColors.forceTotal),
              const SizedBox(width: 16),
              _RawCell('SUAVIZADO', '${smoothed.toStringAsFixed(1)} N',
                  AppColors.primary),
              const SizedBox(width: 16),
              _RawCell(
                  'ΔRAW-SMA',
                  '${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(1)} N',
                  diff.abs() > 20
                      ? AppColors.danger
                      : context.col.textSecondary),
              const Spacer(),
              _RawCell('MUESTRAS', '${live.samplesReceived}',
                  context.col.textSecondary),
            ],
          ),
        ],
      ),
    );
  }
}

class _RawCell extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _RawCell(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.robotoMono(
                fontSize: 9, color: context.col.textSecondary)),
        Text(value,
            style: GoogleFonts.robotoMono(
                fontSize: 13,
                color: color,
                fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 40, color: context.col.border);
}

class _NotConnected extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.usb_off, size: 64, color: context.col.textDisabled),
          const SizedBox(height: 16),
          Text('Plataforma no conectada',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(color: context.col.textSecondary)),
          const SizedBox(height: 8),
          Text(
              'Conecta el RECEPTOR por USB para ver la señal en tiempo real.',
              style:
                  TextStyle(color: context.col.textDisabled, fontSize: 13),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
