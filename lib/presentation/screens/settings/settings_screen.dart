import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/algorithm_settings.dart';
import '../../../core/constants/physics_constants.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../domain/entities/cell_mapping.dart';
import '../../../data/services/supabase_service.dart';
import '../../providers/language_provider.dart';
import '../../providers/sync_provider.dart';
import '../../theme/app_theme.dart';

// ── AppSettings data class ────────────────────────────────────────────────────

class AppSettings {
  final double platformSeparationCm;
  /// Physical platform width (mediolateral axis), default 35 cm.
  final double platformWidthCm;
  /// Physical platform length (anteroposterior axis), default 55 cm.
  final double platformLengthCm;
  final bool showRawData;
  final bool autoSaveTests;
  final bool soundFeedback;
  final bool engineerMode;
  final String weightUnit;   // 'kg' or 'lb'
  final String heightUnit;   // 'cm' or 'in'
  final String language;     // 'es' or 'en'
  final String themeMode;    // 'system', 'dark', 'light'
  final int    serialBaudRate; // 9600 | 19200 | 38400 | 57600 | 115200 | 230400 | 460800 | 921600
  final PlatformOrientation platformOrientation;
  final CellMapping? cellMappingA;
  final CellMapping? cellMappingB;
  final AlgorithmSettings algo;

  const AppSettings({
    this.platformSeparationCm = 30.0,
    this.platformWidthCm      = 35.0,
    this.platformLengthCm     = 55.0,
    this.showRawData          = false,
    this.autoSaveTests        = true,
    this.soundFeedback        = true,
    this.engineerMode         = false,
    this.weightUnit           = 'kg',
    this.heightUnit           = 'cm',
    this.language             = 'es',
    this.themeMode            = 'dark',
    this.serialBaudRate       = 921600,
    this.platformOrientation  = PlatformOrientation.dualVertical,
    this.cellMappingA,
    this.cellMappingB,
    this.algo                 = const AlgorithmSettings(),
  });

  ThemeMode get flutterThemeMode => switch (themeMode) {
    'dark'    => ThemeMode.dark,
    'outdoor' => ThemeMode.light,   // outdoor usa el slot claro con paleta alto contraste
    'light'   => ThemeMode.light,
    _         => ThemeMode.dark,    // default: oscuro
  };

  // ── Convenience getters for algorithm choices ─────────────────────────────

  /// true  → impulse-momentum method;  false → flight-time method.
  bool get useImpulseHeight    => algo.jumpHeight  == JumpHeightMethod.impulseMomentum;

  /// true  → Limb Symmetry Index (LSI);  false → Asymmetry Index (AI).
  bool get useLsiSymmetry      => algo.symmetry    == SymmetryMethod.limbSymmetryIndex;

  /// true  → onset = BW + 5×SD;  false → onset = BW + 50 N.
  bool get useStatImtpOnset    => algo.imtpOnset   == ImtpOnsetMethod.statisticalSD;

  /// true  → adaptive 5×SD threshold;  false → fixed 80 N.
  bool get useAdaptiveUnweight => algo.unweighting == UnweightingMethod.adaptive5SD;

  /// true  → FFT f₉₅;  false → zero-crossing rate.
  bool get useFftCopFreq       => algo.copFrequency == CopFrequencyMethod.fft95;

  AppSettings copyWith({
    double? platformSeparationCm,
    double? platformWidthCm,
    double? platformLengthCm,
    bool? showRawData,
    bool? autoSaveTests,
    bool? soundFeedback,
    bool? engineerMode,
    String? weightUnit,
    String? heightUnit,
    String? language,
    String? themeMode,
    int?    serialBaudRate,
    PlatformOrientation? platformOrientation,
    CellMapping? cellMappingA,
    CellMapping? cellMappingB,
    AlgorithmSettings? algo,
  }) => AppSettings(
    platformSeparationCm: platformSeparationCm ?? this.platformSeparationCm,
    platformWidthCm:      platformWidthCm      ?? this.platformWidthCm,
    platformLengthCm:     platformLengthCm     ?? this.platformLengthCm,
    showRawData:          showRawData          ?? this.showRawData,
    autoSaveTests:        autoSaveTests        ?? this.autoSaveTests,
    soundFeedback:        soundFeedback        ?? this.soundFeedback,
    engineerMode:         engineerMode         ?? this.engineerMode,
    weightUnit:           weightUnit           ?? this.weightUnit,
    heightUnit:           heightUnit           ?? this.heightUnit,
    language:             language             ?? this.language,
    themeMode:            themeMode            ?? this.themeMode,
    serialBaudRate:       serialBaudRate       ?? this.serialBaudRate,
    platformOrientation:  platformOrientation  ?? this.platformOrientation,
    cellMappingA:         cellMappingA         ?? this.cellMappingA,
    cellMappingB:         cellMappingB         ?? this.cellMappingB,
    algo:                 algo                 ?? this.algo,
  );
}

// ── SettingsNotifier ──────────────────────────────────────────────────────────

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier() : super(const AppSettings()) { _load(); }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();

    // Helper: safely parse enum by name, fallback to default.
    T _e<T extends Enum>(List<T> values, String? key, T fallback) {
      final name = p.getString(key ?? '');
      if (name == null) return fallback;
      try { return values.byName(name); } catch (e) { debugPrint('[Settings] Enum parse error for "$name": $e'); return fallback; }
    }

    state = AppSettings(
      platformSeparationCm: p.getDouble('platform_sep_cm')  ?? 30.0,
      showRawData:   p.getBool('show_raw')       ?? false,
      autoSaveTests: p.getBool('auto_save')      ?? true,
      soundFeedback: p.getBool('sound')          ?? true,
      engineerMode:  p.getBool('engineer_mode')  ?? false,
      weightUnit:    p.getString('weight_unit')  ?? 'kg',
      heightUnit:    p.getString('height_unit')  ?? 'cm',
      language:       p.getString('language')      ?? 'es',
      themeMode:      p.getString('theme_mode')    ?? 'dark',
      serialBaudRate: p.getInt('serial_baud_rate') ?? 921600,
      platformOrientation: _e(PlatformOrientation.values, 'platform_orientation',
                              PlatformOrientation.dualVertical),
      cellMappingA: _tryLoadMapping(p, 'cell_mapping_a'),
      cellMappingB: _tryLoadMapping(p, 'cell_mapping_b'),
      algo: AlgorithmSettings(
        jumpHeight:   _e(JumpHeightMethod.values,   'algo_jump_height',
                        JumpHeightMethod.impulseMomentum),
        peakPower:    _e(PeakPowerMethod.values,    'algo_peak_power',
                        PeakPowerMethod.sayers),
        symmetry:     _e(SymmetryMethod.values,     'algo_symmetry',
                        SymmetryMethod.asymmetryIndex),
        imtpOnset:    _e(ImtpOnsetMethod.values,    'algo_imtp_onset',
                        ImtpOnsetMethod.statisticalSD),
        unweighting:  _e(UnweightingMethod.values,  'algo_unweighting',
                        UnweightingMethod.adaptive5SD),
        copFrequency: _e(CopFrequencyMethod.values, 'algo_cop_freq',
                        CopFrequencyMethod.fft95),
      ),
    );
  }

  static CellMapping? _tryLoadMapping(SharedPreferences p, String key) {
    final json = p.getString(key);
    if (json == null || json.isEmpty) return null;
    try { return CellMapping.fromJson(json); } catch (_) { return null; }
  }

  Future<void> _persist() async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble('platform_sep_cm',    state.platformSeparationCm);
    await p.setBool('show_raw',          state.showRawData);
    await p.setBool('auto_save',         state.autoSaveTests);
    await p.setBool('sound',             state.soundFeedback);
    await p.setBool('engineer_mode',     state.engineerMode);
    await p.setString('weight_unit',     state.weightUnit);
    await p.setString('height_unit',     state.heightUnit);
    await p.setString('language',        state.language);
    await p.setString('theme_mode',      state.themeMode);
    await p.setInt('serial_baud_rate',   state.serialBaudRate);
    await p.setString('platform_orientation', state.platformOrientation.name);
    if (state.cellMappingA != null) {
      await p.setString('cell_mapping_a', state.cellMappingA!.toJson());
    }
    if (state.cellMappingB != null) {
      await p.setString('cell_mapping_b', state.cellMappingB!.toJson());
    }
    // Algorithm settings
    await p.setString('algo_jump_height', state.algo.jumpHeight.name);
    await p.setString('algo_peak_power',  state.algo.peakPower.name);
    await p.setString('algo_symmetry',    state.algo.symmetry.name);
    await p.setString('algo_imtp_onset',  state.algo.imtpOnset.name);
    await p.setString('algo_unweighting', state.algo.unweighting.name);
    await p.setString('algo_cop_freq',    state.algo.copFrequency.name);
  }

  void update(AppSettings Function(AppSettings) updater) {
    state = updater(state);
    _persist();
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AppSettings>(
        (_) => SettingsNotifier());

// ── Screen ────────────────────────────────────────────────────────────────────

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings    = ref.watch(settingsProvider);
    final notifier    = ref.read(settingsProvider.notifier);
    final currentLang = ref.watch(languageProvider);
    final langNotifier = ref.read(languageProvider.notifier);

    void upd(AppSettings Function(AppSettings) fn) => notifier.update(fn);

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.get('configure_settings')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          // ── Idioma / Language ────────────────────────────────────────────
          _SectionHeader(AppStrings.get('language')),
          _SettingCard(children: [
            _PickerTile(
              label:    AppStrings.get('language'),
              options:  const ['es', 'en'],
              labels:   [AppStrings.get('spanish'), AppStrings.get('english')],
              selected: currentLang,
              onChanged: (v) {
                langNotifier.setLanguage(v);
                // Keep AppSettings.language in sync so it is included in
                // future SharedPreferences loads.
                upd((s) => s.copyWith(language: v));
              },
            ),
          ]),

          const SizedBox(height: 16),

          // ── Apariencia ──────────────────────────────────────────────────
          _SectionHeader(AppStrings.get('appearance')),
          _SettingCard(children: [
            _PickerTile(
              label:    AppStrings.get('theme'),
              options:  const ['dark', 'light', 'outdoor'],
              labels:   [AppStrings.get('dark_theme'), AppStrings.get('light_theme'), AppStrings.get('outdoor_theme')],
              selected: settings.themeMode,
              onChanged: (v) => upd((s) => s.copyWith(themeMode: v)),
            ),
          ]),

          const SizedBox(height: 16),

          // ── Hardware ────────────────────────────────────────────────────
          _SectionHeader(AppStrings.get('hardware')),
          _SettingCard(children: [
            _SliderTile(
              label: AppStrings.get('platform_separation'),
              subtitle: AppStrings.get('platform_separation_subtitle'),
              value: settings.platformSeparationCm,
              min: 20, max: 60, unit: 'cm',
              onChanged: (v) =>
                  upd((s) => s.copyWith(platformSeparationCm: v.roundToDouble())),
            ),
            Divider(color: context.col.border, height: 1),
            _PickerTile(
              label:    AppStrings.get('serial_baud_rate'),
              subtitle: AppStrings.get('serial_baud_rate_subtitle'),
              options:  const ['9600', '19200', '57600', '115200', '230400', '460800', '921600'],
              selected: settings.serialBaudRate.toString(),
              onChanged: (v) => upd((s) => s.copyWith(serialBaudRate: int.parse(v))),
            ),
          ]),

          const SizedBox(height: 16),

          // ── Unidades ────────────────────────────────────────────────────
          _SectionHeader(AppStrings.get('weight_unit')),
          _SettingCard(children: [
            _PickerTile(
              label:    AppStrings.get('weight_unit'),
              options:  const ['kg', 'lb'],
              selected: settings.weightUnit,
              onChanged: (v) => upd((s) => s.copyWith(weightUnit: v)),
            ),
            Divider(color: context.col.border, height: 1),
            _PickerTile(
              label:    AppStrings.get('jump_height_unit'),
              options:  const ['cm', 'in'],
              selected: settings.heightUnit,
              onChanged: (v) => upd((s) => s.copyWith(heightUnit: v)),
            ),
          ]),

          const SizedBox(height: 16),

          // ── Tests ───────────────────────────────────────────────────────
          _SectionHeader(AppStrings.get('tests_section')),
          _SettingCard(children: [
            _SwitchTile(
              label:    AppStrings.get('auto_save_tests'),
              subtitle: AppStrings.get('auto_save_subtitle'),
              value:    settings.autoSaveTests,
              onChanged: (v) =>
                  upd((s) => s.copyWith(autoSaveTests: v)),
            ),
            Divider(color: context.col.border, height: 1),
            _SwitchTile(
              label:    AppStrings.get('sound_feedback'),
              subtitle: AppStrings.get('sound_feedback_subtitle'),
              value:    settings.soundFeedback,
              onChanged: (v) => upd((s) => s.copyWith(soundFeedback: v)),
            ),
          ]),

          const SizedBox(height: 16),

          // ── Avanzado ────────────────────────────────────────────────────
          _SectionHeader(AppStrings.get('advanced')),
          _SettingCard(children: [
            _SwitchTile(
              label:    AppStrings.get('show_raw_data'),
              subtitle: AppStrings.get('show_raw_subtitle'),
              value:    settings.showRawData,
              onChanged: (v) => upd((s) => s.copyWith(showRawData: v)),
            ),
            Divider(color: context.col.border, height: 1),
            _SwitchTile(
              label:    AppStrings.get('engineer_mode'),
              subtitle: AppStrings.get('engineer_mode_subtitle'),
              value:    settings.engineerMode,
              onChanged: (v) => upd((s) => s.copyWith(engineerMode: v)),
            ),
          ]),

          const SizedBox(height: 16),

          // ── Configuración Avanzada (algoritmos) ─────────────────────────
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              title: Text(AppStrings.get('advanced_config'),
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.col.textPrimary)),
              subtitle: Text(AppStrings.get('advanced_config_subtitle'),
                  style: TextStyle(fontSize: 11, color: context.col.textSecondary)),
              leading: Icon(Icons.science_outlined,
                  color: context.col.textSecondary, size: 20),
              collapsedIconColor: context.col.textSecondary,
              iconColor: AppColors.primary,
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              children: [

                // Saltos
                _AlgoSubHeader(AppStrings.get('jumps_section')),
                _SettingCard(children: [
                  _PickerTile(
                    label:    AppStrings.get('jump_height_method'),
                    options:  const ['flightTime', 'impulseMomentum'],
                    labels:   [AppStrings.get('flight_time_method'), AppStrings.get('impulse_momentum_method')],
                    selected: settings.algo.jumpHeight.name,
                    subtitle: settings.algo.jumpHeight == JumpHeightMethod.impulseMomentum
                        ? AppStrings.get('impulse_momentum_desc')
                        : AppStrings.get('flight_time_desc'),
                    onChanged: (v) => upd((s) => s.copyWith(
                        algo: s.algo.copyWith(
                            jumpHeight: JumpHeightMethod.values.byName(v)))),
                  ),
                  Divider(color: context.col.border, height: 1),
                  _PickerTile(
                    label:    AppStrings.get('peak_power'),
                    options:  const ['sayers', 'harman', 'impulseBased'],
                    labels:   [AppStrings.get('sayers_method'), AppStrings.get('harman_method'), AppStrings.get('impulse_based')],
                    selected: settings.algo.peakPower.name,
                    subtitle: switch (settings.algo.peakPower) {
                      PeakPowerMethod.sayers       => AppStrings.get('sayers_eq'),
                      PeakPowerMethod.harman       => AppStrings.get('harman_eq'),
                      PeakPowerMethod.impulseBased => AppStrings.get('impulse_based_desc'),
                    },
                    onChanged: (v) => upd((s) => s.copyWith(
                        algo: s.algo.copyWith(
                            peakPower: PeakPowerMethod.values.byName(v)))),
                  ),
                  Divider(color: context.col.border, height: 1),
                  _PickerTile(
                    label:    AppStrings.get('symmetry_index'),
                    options:  const ['asymmetryIndex', 'limbSymmetryIndex'],
                    labels:   [AppStrings.get('asymmetry_index_key'), AppStrings.get('limb_symmetry_index')],
                    selected: settings.algo.symmetry.name,
                    subtitle: settings.algo.symmetry == SymmetryMethod.limbSymmetryIndex
                        ? AppStrings.get('lsi_desc')
                        : AppStrings.get('ai_desc'),
                    onChanged: (v) => upd((s) => s.copyWith(
                        algo: s.algo.copyWith(
                            symmetry: SymmetryMethod.values.byName(v)))),
                  ),
                ]),

                const SizedBox(height: 8),

                // Detección de fases
                _AlgoSubHeader(AppStrings.get('phase_detection')),
                _SettingCard(children: [
                  _PickerTile(
                    label:    AppStrings.get('movement_onset'),
                    options:  const ['fixed80N', 'adaptive5SD'],
                    labels:   [AppStrings.get('fixed_80n'), AppStrings.get('adaptive_5sd')],
                    selected: settings.algo.unweighting.name,
                    subtitle: settings.algo.unweighting == UnweightingMethod.adaptive5SD
                        ? AppStrings.get('adaptive_5sd_desc')
                        : AppStrings.get('fixed_80n_desc'),
                    onChanged: (v) => upd((s) => s.copyWith(
                        algo: s.algo.copyWith(
                            unweighting: UnweightingMethod.values.byName(v)))),
                  ),
                ]),

                const SizedBox(height: 8),

                // IMTP
                _AlgoSubHeader(AppStrings.get('imtp_section')),
                _SettingCard(children: [
                  _PickerTile(
                    label:    AppStrings.get('pull_onset'),
                    options:  const ['fixedThreshold', 'statisticalSD'],
                    labels:   [AppStrings.get('bw_50n'), AppStrings.get('adaptive_5sd')],
                    selected: settings.algo.imtpOnset.name,
                    subtitle: settings.algo.imtpOnset == ImtpOnsetMethod.statisticalSD
                        ? AppStrings.get('stat_sd_desc')
                        : AppStrings.get('bw_50n_desc'),
                    onChanged: (v) => upd((s) => s.copyWith(
                        algo: s.algo.copyWith(
                            imtpOnset: ImtpOnsetMethod.values.byName(v)))),
                  ),
                ]),

                const SizedBox(height: 8),

                // CoP / Balance
                _AlgoSubHeader(AppStrings.get('cop_section')),
                _SettingCard(children: [
                  _PickerTile(
                    label:    AppStrings.get('dominant_frequency'),
                    options:  const ['zeroCrossing', 'fft95'],
                    labels:   [AppStrings.get('zero_crossing'), AppStrings.get('fft_f95')],
                    selected: settings.algo.copFrequency.name,
                    subtitle: settings.algo.copFrequency == CopFrequencyMethod.fft95
                        ? AppStrings.get('fft_desc')
                        : AppStrings.get('zero_crossing_desc'),
                    onChanged: (v) => upd((s) => s.copyWith(
                        algo: s.algo.copyWith(
                            copFrequency: CopFrequencyMethod.values.byName(v)))),
                  ),
                ]),

                const SizedBox(height: 8),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Sincronización ──────────────────────────────────────────────
          _SectionHeader(AppStrings.get('cloud_sync')),
          const _SyncSection(),

          const SizedBox(height: 16),

          // ── Acerca de ───────────────────────────────────────────────────
          _SectionHeader(AppStrings.get('about')),
          _SettingCard(children: [
            _InfoTile(label: AppStrings.get('version'), value: '1.0.0'),
            Divider(color: context.col.border, height: 1),
            _InfoTile(label: AppStrings.get('firmware_supported'), value: 'v2.3+'),
            Divider(color: context.col.border, height: 1),
            _InfoTile(
                label: AppStrings.get('sampling_frequency'),
                value: '${PhysicsConstants.samplingRateHz} Hz'),
            Divider(color: context.col.border, height: 1),
            _InfoTile(
                label: AppStrings.get('baud_rate'),
                value: '${PhysicsConstants.baudRate}'),
          ]),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ── Section / sub-header widgets ─────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(title.toUpperCase(), style: IXTextStyles.sectionHeader()),
  );
}

class _AlgoSubHeader extends StatelessWidget {
  final String title;
  const _AlgoSubHeader(this.title);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6, top: 4, left: 2),
    child: Text(
      title,
      style: TextStyle(
        color: context.col.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
      ),
    ),
  );
}

class _SettingCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingCard({required this.children});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color:        context.col.surface,
      borderRadius: BorderRadius.circular(12),
      border:       Border.all(color: context.col.border),
    ),
    child: Column(children: children),
  );
}

// ── Tile widgets ──────────────────────────────────────────────────────────────

class _SwitchTile extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchTile({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => SwitchListTile(
    title: Text(label,
        style: TextStyle(color: context.col.textPrimary,
            fontSize: 14, fontWeight: FontWeight.w500)),
    subtitle: Text(subtitle,
        style: TextStyle(color: context.col.textSecondary, fontSize: 12)),
    value: value,
    activeColor: AppColors.primary,
    onChanged: onChanged,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
  );
}

/// A horizontally arranged picker row with an optional subtitle formula line.
class _PickerTile extends StatelessWidget {
  final String label;
  final List<String> options;
  final List<String>? labels;
  final String selected;
  final ValueChanged<String> onChanged;
  final String? subtitle;    // formula / reference shown below the row

  const _PickerTile({
    required this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.labels,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
              16, 12, 16, subtitle != null ? 2 : 12),
          child: Row(
            children: [
              Expanded(
                child: Text(label,
                    style: TextStyle(color: cs.onSurface, fontSize: 14,
                        fontWeight: FontWeight.w500)),
              ),
              Wrap(
                spacing: 6,
                children: options.asMap().entries.map((entry) {
                  final opt   = entry.value;
                  final lbl   = labels != null ? labels![entry.key] : opt;
                  final isSel = opt == selected;
                  return GestureDetector(
                    onTap: () => onChanged(opt),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color:        isSel
                            ? AppColors.primary.withAlpha(51)
                            : cs.surface,
                        borderRadius: BorderRadius.circular(6),
                        border:       Border.all(
                          color: isSel
                              ? AppColors.primary
                              : context.col.border,
                        ),
                      ),
                      child: Text(lbl,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isSel
                                ? AppColors.primary
                                : context.col.textSecondary,
                          )),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text(
              subtitle!,
              style: TextStyle(
                color:      context.col.textDisabled,
                fontSize:   11,
                fontStyle:  FontStyle.italic,
              ),
            ),
          ),
      ],
    );
  }
}

class _SliderTile extends StatelessWidget {
  final String label;
  final String? subtitle;
  final double value;
  final double min;
  final double max;
  final String unit;
  final ValueChanged<double> onChanged;
  const _SliderTile({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.unit,
    required this.onChanged,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(color: context.col.textPrimary,
                    fontSize: 14, fontWeight: FontWeight.w500)),
            Text('${value.toInt()} $unit',
                style: IXTextStyles.metricValue(color: AppColors.primary)
                    .copyWith(fontSize: 14)),
          ],
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              subtitle!,
              style: TextStyle(fontSize: 11, color: context.col.textSecondary),
            ),
          ),
        Slider(
          value:       value,
          min:         min,
          max:         max,
          divisions:   ((max - min) / 5).round(),
          activeColor:   AppColors.primary,
          inactiveColor: context.col.border,
          onChanged:   onChanged,
        ),
      ],
    ),
  );
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;
  const _InfoTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    title: Text(label,
        style: TextStyle(color: context.col.textPrimary, fontSize: 14)),
    trailing: Text(value,
        style: GoogleFonts.robotoMono(
            color: context.col.textSecondary, fontSize: 13)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
  );
}

// ── Sync section ─────────────────────────────────────────────────────────────

class _SyncSection extends ConsumerStatefulWidget {
  const _SyncSection();

  @override
  ConsumerState<_SyncSection> createState() => _SyncSectionState();
}

class _SyncSectionState extends ConsumerState<_SyncSection> {
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  bool _obscure  = true;
  bool _isSignUp = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!SupabaseService.isConfigured) {
      return _SettingCard(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.cloud_off,
                  color: AppColors.textSecondary, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  AppStrings.get('sync_not_available'),
                  style: TextStyle(
                      fontSize: 11,
                      color: context.col.textSecondary,
                      height: 1.5),
                ),
              ),
            ],
          ),
        ),
      ]);
    }

    final sync     = ref.watch(syncProvider);
    final notifier = ref.read(syncProvider.notifier);

    return _SettingCard(
      children: [
        sync.isAuthenticated
            ? _buildAuthenticated(context, sync, notifier)
            : _buildLoginForm(context, sync, notifier),
      ],
    );
  }

  // ── Authenticated view ────────────────────────────────────────────────────

  Widget _buildAuthenticated(
      BuildContext context, SyncState sync, SyncNotifier notifier) {
    final col = context.col;

    String lastSyncText = AppStrings.get('sync_synced');
    if (sync.lastSyncAt != null) {
      try {
        lastSyncText =
            '${AppStrings.get('sync_last_sync')}: ${DateFormat("d MMM, HH:mm", AppStrings.currentLanguage).format(sync.lastSyncAt!)}';
      } catch (e) {
        debugPrint('[Settings] Date format error: $e');
        lastSyncText =
            '${AppStrings.get('sync_last_sync')}: ${sync.lastSyncAt!.toLocal().toString().substring(0, 16)}';
      }
    }

    final statusLabel = switch (sync.status) {
      SyncStatus.syncing => AppStrings.get('sync_syncing'),
      SyncStatus.success => lastSyncText,
      SyncStatus.error   => '${AppStrings.get('sync_error_prefix')}: ${sync.errorMessage ?? AppStrings.get('sync_error_unknown')}',
      _ => sync.pendingCount > 0
          ? '${sync.pendingCount} ${AppStrings.get('sync_pending_sessions')}'
          : AppStrings.get('sync_no_pending'),
    };

    final statusColor = sync.status == SyncStatus.error
        ? AppColors.danger
        : sync.pendingCount > 0
            ? AppColors.warning
            : col.textSecondary;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Success banner (shown after register or sync) ──────────────
          if (sync.successMessage != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.success.withAlpha(25),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.success.withAlpha(80)),
              ),
              child: Row(children: [
                const Icon(Icons.check_circle_outline,
                    color: AppColors.success, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(sync.successMessage!,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.success)),
                ),
              ]),
            ),
            const SizedBox(height: 12),
          ],

          // ── Account row ────────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.cloud_done,
                  color: AppColors.success, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(sync.userEmail ?? '',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: col.textPrimary)),
                    const SizedBox(height: 2),
                    Text(statusLabel,
                        style: TextStyle(fontSize: 11, color: statusColor)),
                  ],
                ),
              ),
              TextButton(
                onPressed: notifier.signOut,
                style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                child: Text(AppStrings.get('sync_sign_out'),
                    style: const TextStyle(color: AppColors.danger, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Sync button ────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: sync.isBusy ? null : notifier.syncPending,
              icon: sync.isBusy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.textOnPrimary))
                  : const Icon(Icons.sync, size: 16),
              label: Text(
                  sync.isBusy ? AppStrings.get('sync_syncing') : AppStrings.get('sync_now'),
                  style: const TextStyle(fontSize: 13)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.textOnPrimary,
                disabledBackgroundColor: AppColors.primary.withAlpha(128),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Botón para forzar re-sincronización completa
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: sync.isBusy ? null : () async {
                await notifier.syncPending(forceAll: true);
              },
              icon: const Icon(Icons.sync_problem, size: 16),
              label: Text(AppStrings.get('resync_all'), style: const TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.warning,
                side: BorderSide(color: AppColors.warning.withAlpha(150)),
                padding: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Login / register form ─────────────────────────────────────────────────

  Widget _buildLoginForm(
      BuildContext context, SyncState sync, SyncNotifier notifier) {
    final col = context.col;

    InputDecoration _fieldDeco(String label) => InputDecoration(
          labelText: label,
          labelStyle:
              TextStyle(color: col.textSecondary, fontSize: 13),
          filled: true,
          fillColor: col.background,
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: col.border)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: col.border)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  const BorderSide(color: AppColors.primary)),
        );

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.cloud_upload,
                color: AppColors.textSecondary, size: 18),
            const SizedBox(width: 8),
            Text(
              _isSignUp
                  ? AppStrings.get('sync_create_account')
                  : AppStrings.get('sync_account_title'),
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: col.textPrimary),
            ),
          ]),
          const SizedBox(height: 12),

          // Email
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: _fieldDeco(AppStrings.get('sync_email')),
            style: TextStyle(color: col.textPrimary, fontSize: 13),
          ),
          const SizedBox(height: 8),

          // Password
          TextField(
            controller: _passCtrl,
            obscureText: _obscure,
            decoration: _fieldDeco(AppStrings.get('sync_password')).copyWith(
              suffixIcon: IconButton(
                icon: Icon(
                    _obscure
                        ? Icons.visibility_off
                        : Icons.visibility,
                    color: col.textSecondary,
                    size: 18),
                onPressed: () =>
                    setState(() => _obscure = !_obscure),
              ),
            ),
            style: TextStyle(color: col.textPrimary, fontSize: 13),
          ),

          // Error
          if (sync.errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(sync.errorMessage!,
                style: const TextStyle(
                    color: AppColors.danger, fontSize: 11)),
          ],

          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: ElevatedButton(
                onPressed: sync.isBusy
                    ? null
                    : () {
                        final email = _emailCtrl.text.trim();
                        final pass  = _passCtrl.text;
                        if (_isSignUp) {
                          notifier.signUp(email, pass);
                        } else {
                          notifier.signIn(email, pass);
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.textOnPrimary,
                  disabledBackgroundColor:
                      AppColors.primary.withAlpha(128),
                  padding:
                      const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: sync.isBusy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.textOnPrimary))
                    : Text(
                        _isSignUp
                            ? AppStrings.get('sync_register')
                            : AppStrings.get('sync_sign_in'),
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () =>
                  setState(() => _isSignUp = !_isSignUp),
              child: Text(
                  _isSignUp ? AppStrings.get('sync_already_have_account') : AppStrings.get('sync_register'),
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.primary)),
            ),
          ]),
        ],
      ),
    );
  }
}
