import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/l10n/app_strings.dart';

/// Manages the active UI language ('es' or 'en').
///
/// At startup, [initLanguage] must be called (from main.dart) to restore the
/// saved preference and prime [AppStrings].  After that, any widget that reads
/// [languageProvider] will rebuild whenever the language changes.
class LanguageNotifier extends StateNotifier<String> {
  LanguageNotifier(String initial) : super(initial) {
    AppStrings.setLanguage(initial);
  }

  /// Persists [lang] to SharedPreferences, updates [AppStrings] and notifies
  /// all listeners so the UI rebuilds.
  Future<void> setLanguage(String lang) async {
    if (lang != state) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('language', lang);
      AppStrings.setLanguage(lang);
      state = lang;
    }
  }
}

/// Global language provider.  Read initial value from SharedPreferences before
/// calling [ProviderScope] (see main.dart).
final languageProvider =
    StateNotifierProvider<LanguageNotifier, String>((ref) {
  // SettingsNotifier also stores 'language', so we read from the same key.
  // The initial value is supplied by overrideWithValue in the ProviderScope
  // created in main.dart, or defaults to 'es'.
  return LanguageNotifier('es');
});

/// Call once in main() after SharedPreferences is available.
/// Returns the saved language code so it can be passed as an override.
Future<String> initLanguage() async {
  final prefs = await SharedPreferences.getInstance();
  final lang = prefs.getString('language') ?? 'es';
  AppStrings.setLanguage(lang);
  return lang;
}
