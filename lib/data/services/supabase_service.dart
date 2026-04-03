import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// Wrapper around the Supabase client.
///
/// Credentials are embedded at compile time. Override via:
///   --dart-define=SUPABASE_URL=https://xxxx.supabase.co
///   --dart-define=SUPABASE_ANON_KEY=eyJhbGci...
///
/// The anon key is a public client key — Row Level Security on the server
/// is what enforces access control.
class SupabaseService {
  // Production credentials embedded as defaults.
  // Override at build time with --dart-define=SUPABASE_URL=... / SUPABASE_ANON_KEY=...
  static const _url = String.fromEnvironment(
      'SUPABASE_URL',
      defaultValue: 'https://rldtkomtclolhbmrphgh.supabase.co');
  static const _key = String.fromEnvironment(
      'SUPABASE_ANON_KEY',
      defaultValue:
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.'
          'eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJsZHRrb210Y2xvbGhibXJwaGdoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM5NzQ1OTQsImV4cCI6MjA4OTU1MDU5NH0.'
          'uB9S--0zxvmO7UccotZRSen6KLRn4aeOuQe0n8MM5rs');

  /// Always true — production credentials are embedded in the binary.
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
    final raw = e.toString();
    final msg = raw.toLowerCase();
    if (msg.contains('invalid login credentials') ||
        msg.contains('invalid_credentials')) {
      return 'Email o contraseña incorrectos';
    }
    if (msg.contains('user already registered') ||
        msg.contains('already registered')) {
      return 'Este email ya tiene una cuenta';
    }
    if (msg.contains('email not confirmed')) {
      return 'Confirma tu email antes de iniciar sesión';
    }
    if (msg.contains('jwt expired') || msg.contains('token expired')) {
      return 'Sesión expirada. Vuelve a iniciar sesión';
    }
    // Network / server unreachable — could also be Supabase project paused.
    if (msg.contains('network request failed') ||
        msg.contains('socketexception') ||
        msg.contains('connection refused') ||
        msg.contains('failed host lookup') ||
        msg.contains('timeout')) {
      return 'No se pudo conectar con el servidor. '
          'Verifica tu internet o espera un momento si es el primer uso.';
    }
    if (msg.contains('unique constraint') || msg.contains('duplicate key')) {
      return 'Este registro ya existe en la nube';
    }
    if (msg.contains('foreign key') || msg.contains('violates foreign key')) {
      return 'Registro relacionado no encontrado en la nube';
    }
    if (msg.contains('null value') || msg.contains('not-null constraint')) {
      return 'Faltan datos requeridos para sincronizar';
    }
    // Pass through a sanitised version of the raw message so the user can
    // report it precisely.
    final sanitised = raw
        .replaceAll('Exception: ', '')
        .replaceAll('AuthException: ', '')
        .replaceAll('PostgrestException: ', '');
    if (sanitised.length > 120) return '${sanitised.substring(0, 120)}…';
    return sanitised.isNotEmpty ? sanitised : 'Error inesperado. Intenta de nuevo';
  }

  // ── Auth ─────────────────────────────────────────────────────────────────

  Future<void> signIn(String email, String password) async {
    try {
      await _client.auth
          .signInWithPassword(email: email, password: password)
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      throw Exception(_friendlyError(e));
    }
  }

  Future<void> signUp(String email, String password) async {
    try {
      await _client.auth.signUp(email: email, password: password)
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      throw Exception(_friendlyError(e));
    }
  }

  Future<void> signOut() async {
    try {
      await _client.auth.signOut()
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      throw Exception(_friendlyError(e));
    }
  }

  static dynamic _parseMetricsJson(dynamic value) {
    if (value is String) {
      try {
        return jsonDecode(value);
      } catch (e) {
        debugPrint('[Supabase] Corrupt JSON: $e');
        return null; // JSON corrupto — no bloquear la sincronización
      }
    }
    return value;
  }

  // ── Connectivity check ────────────────────────────────────────────────────

  /// Quick SELECT to verify Supabase is reachable and the user token is valid.
  /// Throws a descriptive error if connection fails.
  Future<void> checkConnection() async {
    final user = currentUser;
    if (user == null) throw StateError('No hay sesión activa de Supabase.');
    try {
      await _client.from('athletes').select('id').limit(1)
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      throw Exception('Supabase no accesible: ${_friendlyError(e)}');
    }
  }

  // ── Data sync ─────────────────────────────────────────────────────────────

  /// Upserts an athlete row. Returns the Supabase UUID used.
  ///
  /// Uses onConflict on (user_id, local_id) UNIQUE constraint to merge
  /// instead of failing when the athlete already exists with a different PK.
  Future<String> upsertAthlete(Map<String, dynamic> athlete) async {
    final user = currentUser;
    if (user == null) throw StateError('No hay sesión activa de Supabase.');
    final userId  = user.id;
    final localId = athlete['id'];

    // ── Input validation ──────────────────────────────────────────────────
    final name = (athlete['name'] as String?) ?? '';
    if (name.isEmpty) throw StateError('Nombre del atleta vacío');
    if (name.length > 200) throw StateError('Nombre del atleta demasiado largo');
    final bw = athlete['body_weight_kg'];
    if (bw is num && (bw < 0 || bw > 500)) throw StateError('Peso inválido: $bw kg');

    try {
      // 1. Check if the athlete already exists in Supabase.
      final existing = await _client
          .from('athletes')
          .select('id')
          .eq('user_id', userId)
          .eq('local_id', localId)
          .maybeSingle()
          .timeout(const Duration(seconds: 15));

      // 2. Use the existing UUID or generate a new one.
      final uuid = (existing?['id'] as String?) ??
          (athlete['supabase_uuid'] as String?) ??
          const Uuid().v4();

      // 3. Upsert by PK — never changes `id`, only updates profile fields.
      await _client.from('athletes').upsert(
        {
          'id':             uuid,
          'user_id':        userId,
          'local_id':       localId,
          'name':           athlete['name'] ?? 'Sin nombre',
          'sport':          athlete['sport'],
          'body_weight_kg': athlete['body_weight_kg'],
          'notes':          athlete['notes'],
        },
        onConflict: 'user_id,local_id',
      ).timeout(const Duration(seconds: 15));
      return uuid;
    } catch (e) {
      debugPrint('[Supabase] upsertAthlete failed for local_id=$localId: $e');
      throw Exception(_friendlyError(e));
    }
  }

  /// Upserts a test session. Returns the Supabase UUID used.
  /// [athleteUuid] must not be null — caller must ensure athlete was synced first.
  Future<String> upsertSession(
      Map<String, dynamic> session, String? athleteUuid) async {
    final user = currentUser;
    if (user == null) throw StateError('No hay sesión activa de Supabase.');
    if (athleteUuid == null || athleteUuid.isEmpty) {
      throw StateError('athlete_uuid es null — sincroniza el atleta primero.');
    }
    final testType = session['test_type'] as String?;
    if (testType == null || testType.isEmpty) throw StateError('Tipo de test vacío');
    final userId = user.id;
    final uuid =
        (session['supabase_uuid'] as String?) ?? const Uuid().v4();

    // Sanitise performed_at — SQLite stores as TEXT 'YYYY-MM-DD HH:MM:SS',
    // but Supabase timestamptz needs ISO 8601 with timezone.
    String? performedAt = session['performed_at'] as String?;
    if (performedAt != null && !performedAt.contains('T')) {
      // Convert 'YYYY-MM-DD HH:MM:SS' → 'YYYY-MM-DDTHH:MM:SS+00:00'
      performedAt = '${performedAt.replaceFirst(' ', 'T')}+00:00';
    }

    try {
      await _client.from('test_sessions').upsert({
        'id':               uuid,
        'user_id':          userId,
        'athlete_uuid':     athleteUuid,
        'local_athlete_id': session['athlete_id'],
        'local_id':         session['id'],
        'test_type':        session['test_type'],
        'performed_at':     performedAt,
        'body_weight_kg':   session['body_weight_kg'],
        'platform_count':   session['platform_count'] ?? 1,
        'metrics_json': _parseMetricsJson(session['result_json']),
        'notes': session['notes'],
      }).timeout(const Duration(seconds: 15));
      return uuid;
    } catch (e) {
      debugPrint('[Supabase] upsertSession failed for local_id=${session['id']}: $e');
      throw Exception(_friendlyError(e));
    }
  }
}
