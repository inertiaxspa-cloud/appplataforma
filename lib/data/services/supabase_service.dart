import 'dart:convert';
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

  // ── Friendly error messages ───────────────────────────────────────────────

  /// Converts raw Supabase / network errors into human-readable Spanish strings.
  static String _friendlyError(dynamic e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('invalid login credentials') ||
        msg.contains('invalid_credentials')) {
      return 'Email o contraseña incorrectos';
    }
    if (msg.contains('user already registered') ||
        msg.contains('already registered')) {
      return 'Este email ya tiene una cuenta';
    }
    if (msg.contains('network request failed') ||
        msg.contains('socketexception') ||
        msg.contains('connection refused') ||
        msg.contains('failed host lookup')) {
      return 'Sin conexión a internet. Verifica tu red';
    }
    if (msg.contains('jwt expired') || msg.contains('token expired')) {
      return 'Sesión expirada. Vuelve a iniciar sesión';
    }
    return 'Error inesperado. Intenta de nuevo';
  }

  // ── Auth ─────────────────────────────────────────────────────────────────

  Future<void> signIn(String email, String password) async {
    try {
      await _client.auth
          .signInWithPassword(email: email, password: password);
    } catch (e) {
      throw Exception(_friendlyError(e));
    }
  }

  Future<void> signUp(String email, String password) async {
    try {
      await _client.auth.signUp(email: email, password: password);
    } catch (e) {
      throw Exception(_friendlyError(e));
    }
  }

  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (e) {
      throw Exception(_friendlyError(e));
    }
  }

  static dynamic _parseMetricsJson(dynamic value) {
    if (value is String) {
      try {
        return jsonDecode(value);
      } catch (_) {
        return null; // JSON corrupto — no bloquear la sincronización
      }
    }
    return value;
  }

  // ── Data sync ─────────────────────────────────────────────────────────────

  /// Upserts an athlete row. Returns the Supabase UUID used.
  ///
  /// Strategy: look up the existing row first so we never change its `id` (PK).
  /// Changing the PK would break the FK from test_sessions.athlete_uuid and
  /// cause a 409 Conflict on every subsequent sync attempt.
  Future<String> upsertAthlete(Map<String, dynamic> athlete) async {
    final user = currentUser;
    if (user == null) throw StateError('No hay sesión activa de Supabase.');
    final userId  = user.id;
    final localId = athlete['id'];

    try {
      // 1. Check if the athlete already exists in Supabase.
      final existing = await _client
          .from('athletes')
          .select('id')
          .eq('user_id', userId)
          .eq('local_id', localId)
          .maybeSingle();

      // 2. Use the existing UUID or generate a new one.
      final uuid = (existing?['id'] as String?) ??
          (athlete['supabase_uuid'] as String?) ??
          const Uuid().v4();

      // 3. Upsert by PK — never changes `id`, only updates profile fields.
      await _client.from('athletes').upsert({
        'id':             uuid,
        'user_id':        userId,
        'local_id':       localId,
        'name':           athlete['name'],
        'sport':          athlete['sport'],
        'body_weight_kg': athlete['body_weight_kg'],
        'notes':          athlete['notes'],
      });
      return uuid;
    } catch (e) {
      throw Exception(_friendlyError(e));
    }
  }

  /// Upserts a test session. Returns the Supabase UUID used.
  Future<String> upsertSession(
      Map<String, dynamic> session, String? athleteUuid) async {
    final user = currentUser;
    if (user == null) throw StateError('No hay sesión activa de Supabase.');
    final userId = user.id;
    final uuid =
        (session['supabase_uuid'] as String?) ?? const Uuid().v4();

    try {
      // Upsert por clave primaria (id = UUID). No usar onConflict porque
      // test_sessions no tiene restricción UNIQUE en (user_id, local_id).
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
        'metrics_json': _parseMetricsJson(session['result_json']),
        'notes': session['notes'],
      });
      return uuid;
    } catch (e) {
      throw Exception(_friendlyError(e));
    }
  }
}
