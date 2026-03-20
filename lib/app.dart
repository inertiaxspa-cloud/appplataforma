import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'presentation/screens/home/home_screen.dart';
import 'presentation/screens/monitor/live_monitor_screen.dart';
import 'presentation/screens/athletes/athlete_list_screen.dart';
import 'presentation/screens/connection/connection_screen.dart';
import 'presentation/screens/calibration/calibration_screen.dart';
import 'presentation/screens/tests/cmj_screen.dart';
import 'presentation/screens/tests/sj_screen.dart';
import 'presentation/screens/tests/dj_screen.dart';
import 'presentation/screens/tests/multijump_screen.dart';
import 'presentation/screens/tests/cop_screen.dart';
import 'presentation/screens/tests/imtp_screen.dart';
import 'presentation/screens/history/history_screen.dart';
import 'presentation/screens/settings/settings_screen.dart';
import 'presentation/screens/results/result_detail_screen.dart';
import 'presentation/screens/comparison/comparison_screen.dart';
import 'presentation/theme/app_theme.dart';
import 'domain/entities/test_result.dart';

// ── Router ─────────────────────────────────────────────────────────────────

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/',              builder: (_, __) => const HomeScreen()),
    GoRoute(path: '/monitor',       builder: (_, __) => const LiveMonitorScreen()),
    GoRoute(path: '/athletes',      builder: (_, __) => const AthleteListScreen()),
    GoRoute(path: '/history',       builder: (_, __) => const HistoryScreen()),
    GoRoute(path: '/settings',      builder: (_, __) => const SettingsScreen()),
    GoRoute(path: '/connection',    builder: (_, __) => const ConnectionScreen()),
    GoRoute(path: '/calibration',   builder: (_, __) => const CalibrationScreen()),
    GoRoute(path: '/tests/cmj',     builder: (_, __) => const CmjScreen()),
    GoRoute(path: '/tests/sj',      builder: (_, __) => const SjScreen()),
    GoRoute(path: '/tests/dj',      builder: (_, __) => const DjScreen()),
    GoRoute(path: '/tests/multijump', builder: (_, __) => const MultiJumpScreen()),
    GoRoute(path: '/tests/cop',     builder: (_, __) => const CopScreen()),
    GoRoute(path: '/tests/imtp',    builder: (_, __) => const ImtpScreen()),
    GoRoute(
      path: '/results/:id',
      builder: (_, state) => ResultDetailScreen(
        result: state.extra as TestResult,
      ),
    ),
    GoRoute(
      path: '/compare',
      builder: (_, state) {
        final args = state.extra as Map<String, dynamic>?;
        return ComparisonScreen(
          initialAthleteId: args?['athleteId'] as int?,
          initialTestType:  args?['testType']  as TestType?,
        );
      },
    ),
  ],
);

// ── App entry ──────────────────────────────────────────────────────────────

class InertiaXApp extends ConsumerWidget {
  const InertiaXApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(settingsProvider).flutterThemeMode;
    return MaterialApp.router(
      title: 'InertiaX',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: _router,
    );
  }
}
