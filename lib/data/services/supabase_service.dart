import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// Wrapper around the Supabase client.
///
/// Configure at build time via:
///   flutter build windows \
///     --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///     --dart-define=SUPABASE_ANON_KEY=eyJhbGci...
///
/// If either constant is empty the service is disabled and all calls are no-ops.
class SupabaseService {
  static const _url = String.fromEnvironment(
      'SUPABASE_URL', defaultValue: '');
  static const _key = String.fromEnvironment(
      'SUPABASE_ANON_KEY', defaultValue: '');

  /// true if the app was compiled with Supabase credentials.
  static bool get isConfigured => _url.isNotEmpty && _key.isNotEmpty;

  static final SupabaseService instance = SupabaseService._();
  SupabaseService._();

  /// Must be called from main() before runApp().
  static Future<void> initialize() async {
    if (!isConfigured) return;
    await Supabase.initialize(url: _url, anonKey: _key);
  }

  SupabaseClient get _client => Supabase.instance.client;

  User? get currentUser =>
      isConfigured ? _client.auth.currentUser : null;

  Stream<AuthState> get authStateChanges =>
      isConfigured ? _client.auth.onAuthStateChange : Stream<AuthState>.empty();

  // ── Auth ─────────────────────────────────────────────────────────────────

  Future<void> signIn(String email, String password) async {
    await _client.auth
        .signInWithPassword(email: email, password: password);
  }

  Future<void> signUp(String email, String password) async {
    await _client.auth.signUp(email: email, password: password);
  }

  Future<void> signOut() async => _client.auth.signOut();

  // ── Data sync ─────────────────────────────────────────────────────────────

  /// Upserts an athlete row. Returns the Supabase UUID used.
  Future<String> upsertAthlete(Map<String, dynamic> athlete) async {
    final userId = currentUser!.id;
    final uuid =
        (athlete['supabase_uuid'] as String?) ?? const Uuid().v4();

    // onConflict evita duplicados: si (user_id, local_id) ya existe, actualiza
    await _client.from('athletes').upsert({
      'id':             uuid,
      'user_id':        userId,
      'local_id':       athlete['id'],
      'name':           athlete['name'],
      'sport':          athlete['sport'],
      'body_weight_kg': athlete['body_weight_kg'],
      'notes':          athlete['notes'],
    }, onConflict: 'user_id,local_id');
    return uuid;
  }

  /// Upserts a test session. Returns the Supabase UUID used.
  Future<String> upsertSession(
      Map<String, dynamic> session, String? athleteUuid) async {
    final userId = currentUser!.id;
    final uuid =
        (session['supabase_uuid'] as String?) ?? const Uuid().v4();

    await _client.from('test_sessions').upsert({
      'id':               uuid,
      'user_id':          userId,
      'athlete_uuid':     athleteUuid,
      'local_athlete_id': session['athlete_id'],
      'local_id':         session['id'],
      'test_type':        session['test_type'],
      'performed_at':     session['performed_at'],
      'body_weight_kg':   session['body_weight_kg'],
      'platform_count':   session['platform_count'] ?? 1,
      'metrics_json':     session['result_json'],   // columna real en DB
      'notes':            session['notes'],
    });
    return uuid;
  }
}
