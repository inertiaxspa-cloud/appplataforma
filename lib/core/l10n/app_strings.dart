// ignore_for_file: prefer_single_quotes
/// Simple static i18n helper.
/// Call [AppStrings.setLanguage] once at startup (and on change) with 'es' or 'en'.
/// Use [AppStrings.get] to retrieve a translated string by key.
library app_strings;

class AppStrings {
  AppStrings._();

  static String _lang = 'es';

  /// Update the active language. Should be called from [LanguageNotifier].
  static void setLanguage(String lang) => _lang = lang;

  /// Returns the current active language code ('es' or 'en').
  static String get currentLanguage => _lang;

  static const Map<String, Map<String, String>> _strings = {
    'es': {
      // Navigation
      'home': 'Inicio',
      'athletes': 'Atletas',
      'history': 'Historial',
      'settings': 'Configuración',
      'connect': 'Conectar',
      'calibrate': 'Calibrar',
      // Tests
      'test_cmj': 'Salto con Contramovimiento',
      'test_sj': 'Salto sin Contramovimiento',
      'test_dj': 'Drop Jump',
      'test_multijump': 'Saltos Consecutivos',
      'test_imtp': 'Tracción Isométrica',
      'test_cop': 'Equilibrio y CoP',
      // Actions
      'start': 'Iniciar',
      'cancel': 'Cancelar',
      'save': 'Guardar',
      'delete': 'Eliminar',
      'retry': 'Reintentar',
      'back': 'Volver',
      'finish': 'Terminar',
      'share': 'Compartir',
      'export': 'Exportar',
      // Status
      'loading': 'Cargando...',
      'no_connection': 'Sin conexión',
      'connected': 'Conectado',
      'disconnected': 'Desconectado',
      'calibrated': 'Calibrado',
      'not_calibrated': 'Sin calibrar',
      // Athletes
      'add_athlete': 'Agregar atleta',
      'no_athletes': 'Aún no tienes atletas registrados',
      'no_athletes_sub': 'Agrega tu primer atleta con el botón +',
      'athlete_name': 'Nombre',
      'athlete_sport': 'Deporte',
      'athlete_weight': 'Peso (kg)',
      // History
      'no_history': 'Sin tests registrados',
      'no_history_sub': 'Completa tu primer test para ver el historial aquí',
      // Sync
      'sync': 'Sincronizar',
      'sync_all': 'Re-sincronizar todo',
      'sync_success': 'Sincronización completada',
      'sync_error': 'Error de sincronización',
      // Errors
      'error_connection': 'Sin conexión a internet',
      'error_unexpected': 'Error inesperado. Intenta de nuevo',
      'error_session': 'Sesión expirada. Vuelve a iniciar sesión',
      // Test phases
      'phase_settling': 'Midiendo peso corporal...',
      'phase_waiting': 'Listo. Realiza el salto',
      'phase_flight': '¡En vuelo!',
      'phase_landed': 'Aterrizando...',
      // Results
      'result_jump_height': 'Altura de Salto',
      'result_peak_force': 'Fuerza Pico',
      'result_symmetry': 'Simetría',
      'result_rsi': 'RSI Modificado',
      'result_flight_time': 'Tiempo de Vuelo',
      'result_contact_time': 'Tiempo de Contacto',
      'result_peak_power': 'Potencia Pico',
      'result_impulse': 'Impulso Neto',
    },
    'en': {
      // Navigation
      'home': 'Home',
      'athletes': 'Athletes',
      'history': 'History',
      'settings': 'Settings',
      'connect': 'Connect',
      'calibrate': 'Calibrate',
      // Tests
      'test_cmj': 'Countermovement Jump',
      'test_sj': 'Squat Jump',
      'test_dj': 'Drop Jump',
      'test_multijump': 'Repeated Jumps',
      'test_imtp': 'Isometric Mid-Thigh Pull',
      'test_cop': 'Balance & CoP',
      // Actions
      'start': 'Start',
      'cancel': 'Cancel',
      'save': 'Save',
      'delete': 'Delete',
      'retry': 'Retry',
      'back': 'Back',
      'finish': 'Finish',
      'share': 'Share',
      'export': 'Export',
      // Status
      'loading': 'Loading...',
      'no_connection': 'No connection',
      'connected': 'Connected',
      'disconnected': 'Disconnected',
      'calibrated': 'Calibrated',
      'not_calibrated': 'Not calibrated',
      // Athletes
      'add_athlete': 'Add athlete',
      'no_athletes': 'No athletes registered yet',
      'no_athletes_sub': 'Add your first athlete with the + button',
      'athlete_name': 'Name',
      'athlete_sport': 'Sport',
      'athlete_weight': 'Weight (kg)',
      // History
      'no_history': 'No tests recorded',
      'no_history_sub': 'Complete your first test to see the history here',
      // Sync
      'sync': 'Sync',
      'sync_all': 'Re-sync all',
      'sync_success': 'Sync completed',
      'sync_error': 'Sync error',
      // Errors
      'error_connection': 'No internet connection',
      'error_unexpected': 'Unexpected error. Please try again',
      'error_session': 'Session expired. Please sign in again',
      // Test phases
      'phase_settling': 'Measuring body weight...',
      'phase_waiting': 'Ready. Perform the jump',
      'phase_flight': 'In flight!',
      'phase_landed': 'Landing...',
      // Results
      'result_jump_height': 'Jump Height',
      'result_peak_force': 'Peak Force',
      'result_symmetry': 'Symmetry',
      'result_rsi': 'Modified RSI',
      'result_flight_time': 'Flight Time',
      'result_contact_time': 'Contact Time',
      'result_peak_power': 'Peak Power',
      'result_impulse': 'Net Impulse',
    },
  };

  /// Returns the translated string for [key] in the current language.
  /// Falls back to Spanish if key is missing in the current language.
  /// Returns [key] itself if not found in any language.
  static String get(String key) =>
      _strings[_lang]?[key] ?? _strings['es']![key] ?? key;
}
