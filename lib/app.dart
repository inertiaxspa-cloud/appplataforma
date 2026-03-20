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
import 'presentation/screens/tests/tests_hub_screen.dart';
import 'presentation/screens/history/history_screen.dart';
import 'presentation/screens/settings/settings_screen.dart';
import 'presentation/screens/results/result_detail_screen.dart';
import 'presentation/screens/comparison/comparison_screen.dart';
import 'presentation/theme/app_theme.dart';
import 'domain/entities/test_result.dart';

// ── Shell widget — wraps tab content with NavigationBar ───────────────────

class _AppShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  const _AppShell({required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) {
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Inicio',
          ),
          NavigationDestination(
            icon: Icon(Icons.fitness_center_outlined),
            selectedIcon: Icon(Icons.fitness_center_rounded),
            label: 'Tests',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart_rounded),
            label: 'Historial',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Ajustes',
          ),
        ],
      ),
    );
  }
}

// ── Router ─────────────────────────────────────────────────────────────────

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    // ── Shell with 4 branches (bottom tabs) ──────────────────────────────
    StatefulShellRoute.indexedStack(
      builder: (_, __, shell) => _AppShell(navigationShell: shell),
      branches: [
        // Branch 0: Home
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, __) => const HomeScreen(),
            ),
          ],
        ),
        // Branch 1: Tests hub
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/tests',
              builder: (_, __) => const TestsHubScreen(),
            ),
          ],
        ),
        // Branch 2: History
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/history',
              builder: (_, __) => const HistoryScreen(),
            ),
          ],
        ),
        // Branch 3: Settings
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/settings',
              builder: (_, __) => const SettingsScreen(),
            ),
          ],
        ),
      ],
    ),

    // ── Routes that push over the shell (no bottom nav) ───────────────────
    GoRoute(path: '/monitor',         builder: (_, __) => const LiveMonitorScreen()),
    GoRoute(path: '/athletes',        builder: (_, __) => const AthleteListScreen()),
    GoRoute(path: '/connection',      builder: (_, __) => const ConnectionScreen()),
    GoRoute(path: '/calibration',     builder: (_, __) => const CalibrationScreen()),
    GoRoute(path: '/tests/cmj',       builder: (_, __) => const CmjScreen()),
    GoRoute(path: '/tests/sj',        builder: (_, __) => const SjScreen()),
    GoRoute(path: '/tests/dj',        builder: (_, __) => const DjScreen()),
    GoRoute(path: '/tests/multijump', builder: (_, __) => const MultiJumpScreen()),
    GoRoute(path: '/tests/cop',       builder: (_, __) => const CopScreen()),
    GoRoute(path: '/tests/imtp',      builder: (_, __) => const ImtpScreen()),
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
