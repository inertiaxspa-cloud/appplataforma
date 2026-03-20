import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'data/services/supabase_service.dart';
import 'presentation/providers/language_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Global Flutter error handler ──────────────────────────────────────────
  FlutterError.onError = (FlutterErrorDetails details) {
    debugPrint('[FlutterError] ${details.exceptionAsString()}');
    debugPrint(details.stack?.toString() ?? '');
    // Let Flutter handle fatal errors in debug mode normally.
    if (kDebugMode) {
      FlutterError.presentError(details);
    }
  };

  // ── Custom ErrorWidget builder (replaces red crash screen) ────────────────
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Container(
      color: const Color(0xFF0D0F14),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded,
              color: Color(0xFFEF4444), size: 40),
          const SizedBox(height: 12),
          const Text(
            'Error al cargar vista',
            style: TextStyle(
              color: Color(0xFFE5E7EB),
              fontSize: 16,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.none,
            ),
            textAlign: TextAlign.center,
          ),
          if (kDebugMode) ...[
            const SizedBox(height: 8),
            Text(
              details.exceptionAsString(),
              style: const TextStyle(
                color: Color(0xFF9CA3AF),
                fontSize: 11,
                fontFamily: 'monospace',
                decoration: TextDecoration.none,
              ),
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  };

  await initializeDateFormatting('es', null);
  await SupabaseService.initialize();

  // ── Restore saved language and prime AppStrings ───────────────────────────
  final savedLang = await initLanguage();

  // ── Determine initial route based on onboarding flag ─────────────────────
  final prefs = await SharedPreferences.getInstance();
  final onboardingDone = prefs.getBool('onboarding_done') ?? false;
  final initialRoute = onboardingDone ? '/' : '/welcome';

  runApp(
    ProviderScope(
      overrides: [
        // Seed the languageProvider with the value already read from prefs.
        languageProvider.overrideWith((_) => LanguageNotifier(savedLang)),
      ],
      child: InertiaXApp(initialRoute: initialRoute),
    ),
  );
}
