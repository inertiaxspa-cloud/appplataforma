import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/l10n/app_strings.dart';
import 'presentation/providers/language_provider.dart';
import 'presentation/screens/home/home_screen.dart';
import 'presentation/screens/monitor/live_monitor_screen.dart';
import 'presentation/screens/athletes/athlete_list_screen.dart';
import 'presentation/screens/athletes/athlete_progress_screen.dart';
import 'domain/entities/athlete.dart' show Athlete;
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
import 'presentation/screens/onboarding/welcome_screen.dart';
import 'presentation/screens/onboarding/test_info_screen.dart';
import 'presentation/screens/error/error_screen.dart';
import 'presentation/theme/app_theme.dart';
import 'domain/entities/test_result.dart';

// ── Shell widget — wraps tab content with NavigationBar ───────────────────

class _AppShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;
  const _AppShell({required this.navigationShell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch language so nav labels rebuild when the language changes.
    ref.watch(languageProvider);

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
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home_rounded),
            label: AppStrings.get('home'),
          ),
          const NavigationDestination(
            icon: Icon(Icons.fitness_center_outlined),
            selectedIcon: Icon(Icons.fitness_center_rounded),
            label: 'Tests',
          ),
          NavigationDestination(
            icon: const Icon(Icons.bar_chart_outlined),
            selectedIcon: const Icon(Icons.bar_chart_rounded),
            label: AppStrings.get('history'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings_rounded),
            label: AppStrings.get('settings'),
          ),
        ],
      ),
    );
  }
}

// ── Router factory ─────────────────────────────────────────────────────────

GoRouter _buildRouter(String initialLocation) => GoRouter(
  initialLocation: initialLocation,
  errorPageBuilder: (context, state) => MaterialPage(
    child: ErrorScreen(errorMessage: 'Route not found: ${state.uri}'),
  ),
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
    GoRoute(
      path: '/athletes/progress',
      builder: (_, state) {
        final athlete = state.extra as Athlete?;
        if (athlete == null) return const ErrorScreen(errorMessage: 'No athlete data');
        return AthleteProgressScreen(athlete: athlete);
      },
    ),
    GoRoute(path: '/connection',      builder: (_, __) => const ConnectionScreen()),
    GoRoute(path: '/calibration',     builder: (_, __) => const CalibrationScreen()),
    GoRoute(path: '/tests/cmj',       builder: (_, __) => const CmjScreen()),
    GoRoute(path: '/tests/sj',        builder: (_, __) => const SjScreen()),
    GoRoute(path: '/tests/dj',        builder: (_, __) => const DjScreen()),
    GoRoute(path: '/tests/multijump', builder: (_, __) => const MultiJumpScreen()),
    GoRoute(path: '/tests/cop',       builder: (_, __) => const CopScreen()),
    GoRoute(path: '/tests/imtp',      builder: (_, __) => const ImtpScreen()),
    // Resultados desde historial — solo lectura, NO auto-save
    GoRoute(
      path: '/results/:id',
      builder: (_, state) {
        final result = state.extra as TestResult?;
        if (result == null) return const ErrorScreen(errorMessage: 'No result data');
        return ResultDetailScreen(result: result, isFromHistory: true);
      },
    ),
    // Resultados nuevos (post-test) — auto-save habilitado
    GoRoute(
      path: '/results/new',
      builder: (_, state) {
        final result = state.extra as TestResult?;
        if (result == null) return const ErrorScreen(errorMessage: 'No result data');
        return ResultDetailScreen(result: result, isFromHistory: false);
      },
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
    // ── Onboarding ────────────────────────────────────────────────────────
    GoRoute(
      path: '/welcome',
      builder: (_, __) => const WelcomeScreen(),
    ),
    GoRoute(
      path: '/test-info',
      builder: (_, state) {
        final testType = state.extra as String? ?? '';
        return TestInfoScreen(testType: testType);
      },
    ),
  ],
);

// ── App entry ──────────────────────────────────────────────────────────────

class InertiaXApp extends ConsumerStatefulWidget {
  final String initialRoute;

  const InertiaXApp({super.key, this.initialRoute = '/'});

  @override
  ConsumerState<InertiaXApp> createState() => _InertiaXAppState();
}

class _InertiaXAppState extends ConsumerState<InertiaXApp> {
  // Router created ONCE in initState — never recreated on theme/language rebuild.
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = _buildRouter(widget.initialRoute);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final language = ref.watch(languageProvider);
    return MaterialApp.router(
      title: 'InertiaX Force',
      debugShowCheckedModeBanner: false,
      theme: settings.themeMode == 'outdoor' ? AppTheme.outdoor : AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: settings.flutterThemeMode,
      routerConfig: _router,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('es'),
        Locale('en'),
      ],
      locale: Locale(language),
    );
  }
}
