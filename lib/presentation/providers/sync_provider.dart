import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import '../../core/l10n/app_strings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/datasources/local/database_helper.dart';
import '../../data/services/supabase_service.dart';

// ── State ─────────────────────────────────────────────────────────────────────

enum SyncStatus { unauthenticated, idle, syncing, success, error }

class SyncState {
  final SyncStatus status;
  final int pendingCount;
  final DateTime? lastSyncAt;
  final String? errorMessage;
  final String? userEmail;
  final String? successMessage;

  const SyncState({
    required this.status,
    this.pendingCount = 0,
    this.lastSyncAt,
    this.errorMessage,
    this.userEmail,
    this.successMessage,
  });

  bool get isAuthenticated => userEmail != null;
  bool get isBusy          => status == SyncStatus.syncing;

  SyncState copyWith({
    SyncStatus? status,
    int?        pendingCount,
    DateTime?   lastSyncAt,
    String?     errorMessage,
    String?     userEmail,
    String?     successMessage,
    bool clearError   = false,
    bool clearUser    = false,
    bool clearSuccess = false,
  }) =>
      SyncState(
        status:         status         ?? this.status,
        pendingCount:   pendingCount   ?? this.pendingCount,
        lastSyncAt:     lastSyncAt     ?? this.lastSyncAt,
        errorMessage:   clearError     ? null : (errorMessage   ?? this.errorMessage),
        userEmail:      clearUser      ? null : (userEmail      ?? this.userEmail),
        successMessage: clearSuccess   ? null : (successMessage ?? this.successMessage),
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class SyncNotifier extends StateNotifier<SyncState> {
  StreamSubscription<AuthState>? _authSub;
  bool _syncing = false; // guard contra llamadas concurrentes

  SyncNotifier()
      : super(const SyncState(status: SyncStatus.unauthenticated)) {
    _init();
  }

  void _init() {
    if (!SupabaseService.isConfigured) return;

    // Restore session if already logged in.
    final user = SupabaseService.instance.currentUser;
    if (user != null) {
      state = state.copyWith(
          status: SyncStatus.idle, userEmail: user.email);
      _refreshPendingCount();
    }

    // Watch auth state changes (login / logout / token refresh).
    _authSub =
        SupabaseService.instance.authStateChanges.listen((auth) {
      final u = auth.session?.user;
      if (u != null) {
        state = state.copyWith(
            status: SyncStatus.idle,
            userEmail: u.email,
            clearError: true);
        _refreshPendingCount();
      } else {
        state = const SyncState(
            status: SyncStatus.unauthenticated, pendingCount: 0);
      }
    });
  }

  Future<void> _refreshPendingCount() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.rawQuery(
        "SELECT COUNT(*) AS cnt FROM test_sessions WHERE sync_status = 'pending'");
    final count = (rows.first['cnt'] as int?) ?? 0;
    if (mounted) state = state.copyWith(pendingCount: count);
  }

  // ── Auth ───────────────────────────────────────────────────────────────────

  Future<void> signIn(String email, String password) async {
    state = state.copyWith(status: SyncStatus.syncing, clearError: true);
    try {
      await SupabaseService.instance.signIn(email, password);
      // auth listener will update state to idle + userEmail
    } on AuthException catch (e) {
      if (mounted) {
        state = state.copyWith(
            status: SyncStatus.error, errorMessage: e.message);
      }
    } catch (e) {
      if (mounted) {
        state = state.copyWith(
            status: SyncStatus.error, errorMessage: e.toString());
      }
    }
  }

  Future<void> signUp(String email, String password) async {
    state = state.copyWith(status: SyncStatus.syncing, clearError: true);
    try {
      await SupabaseService.instance.signUp(email, password);
      // Auto-login immediately (works when email confirmation is disabled).
      try {
        await SupabaseService.instance.signIn(email, password);
      } catch (_) {
        // If signIn fails the user needs to verify email first; auth listener
        // will handle state when they eventually confirm.
      }
      if (mounted) {
        final user = SupabaseService.instance.currentUser;
        state = state.copyWith(
          status:         SyncStatus.idle,
          userEmail:      user?.email,
          successMessage: user != null
              ? AppStrings.get('account_created_loggedin')
              : AppStrings.get('account_created_verify'),
          clearError: true,
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        state = state.copyWith(
            status: SyncStatus.error, errorMessage: e.message);
      }
    } catch (e) {
      if (mounted) {
        state = state.copyWith(
            status: SyncStatus.error, errorMessage: e.toString());
      }
    }
  }

  Future<void> signOut() async {
    await SupabaseService.instance.signOut();
    // auth listener handles state reset
  }

  // ── Sync ───────────────────────────────────────────────────────────────────

  /// Marca todas las sesiones como 'pending' para forzar re-sincronización.
  /// No borra supabase_uuid para que el upsert actualice filas existentes
  /// en lugar de crear nuevas (lo que causaría violaciones de clave única).
  Future<void> resetSyncStatus() async {
    final db = await DatabaseHelper.instance.database;
    await db.rawUpdate("UPDATE test_sessions SET sync_status = 'pending'");
    await _refreshPendingCount();
  }

  /// Pushes all sessions with sync_status='pending' or 'error' to Supabase.
  Future<void> syncPending({bool forceAll = false}) async {
    if (!state.isAuthenticated || _syncing) return;
    _syncing = true;

    final db = await DatabaseHelper.instance.database;

    // Re-queue previous errors so they get retried.
    await db.update('test_sessions', {'sync_status': 'pending'},
        where: "sync_status = 'error'");

    // If forceAll, also re-queue 'synced' (useful after Supabase dashboard wipe).
    if (forceAll) {
      await db.update('test_sessions', {'sync_status': 'pending'},
          where: "sync_status = 'synced'");
    }

    state = state.copyWith(status: SyncStatus.syncing, clearError: true);

    String? lastError; // Keep last error detail for user display.

    try {
      // Fetch pending sessions joined with athlete data.
      final rows = await db.rawQuery('''
        SELECT ts.*,
               a.supabase_uuid AS athlete_supabase_uuid,
               a.id      AS a_id,
               a.name    AS a_name,
               a.sport   AS a_sport,
               a.body_weight_kg AS a_bwkg,
               a.notes   AS a_notes
        FROM test_sessions ts
        LEFT JOIN athletes a ON a.id = ts.athlete_id
        WHERE ts.sync_status = 'pending'
        ORDER BY ts.performed_at ASC
      ''');

      // Cache athlete UUIDs to avoid repeated upserts for the same athlete.
      final athleteUuidCache = <int, String>{};

      for (final row in rows) {
        try {
          // ── Ensure athlete has a Supabase UUID ──────────────────────────
          final athleteId  = row['athlete_id'] as int?;
          String? athUuid  = row['athlete_supabase_uuid'] as String?;

          // Use cache first (avoids repeated Supabase calls for same athlete).
          if (athleteId != null && athUuid == null && athleteUuidCache.containsKey(athleteId)) {
            athUuid = athleteUuidCache[athleteId];
          }

          if (athleteId != null && athUuid == null) {
            final athleteRow = <String, dynamic>{
              'id':             row['a_id'],
              'supabase_uuid':  null,
              'name':           row['a_name'],
              'sport':          row['a_sport'],
              'body_weight_kg': row['a_bwkg'],
              'notes':          row['a_notes'],
            };
            athUuid = await SupabaseService.instance.upsertAthlete(athleteRow);
            // Persist UUID locally so future syncs don't repeat this.
            await db.update('athletes', {'supabase_uuid': athUuid},
                where: 'id = ?', whereArgs: [athleteId]);
            athleteUuidCache[athleteId] = athUuid;
          }

          if (athleteId != null && athUuid != null) {
            athleteUuidCache[athleteId] = athUuid;
          }

          // ── Push session ─────────────────────────────────────────────────
          final sessionMap = Map<String, dynamic>.from(row);
          final sessionUuid = await SupabaseService.instance
              .upsertSession(sessionMap, athUuid);

          await db.update(
            'test_sessions',
            {'sync_status': 'synced', 'supabase_uuid': sessionUuid},
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        } catch (e) {
          final errMsg = e.toString().replaceAll('Exception: ', '');
          lastError = errMsg;
          debugPrint('[Sync] Session ${row['id']} failed: $errMsg');
          await db.update('test_sessions',
              {'sync_status': 'error'},
              where: 'id = ?', whereArgs: [row['id']]);
        }
      }

      // Re-count remaining and errors.
      final rem = await db.rawQuery(
          "SELECT COUNT(*) AS cnt FROM test_sessions WHERE sync_status = 'pending'");
      final pendingLeft = (rem.first['cnt'] as int?) ?? 0;
      final errRows = await db.rawQuery(
          "SELECT COUNT(*) AS cnt FROM test_sessions WHERE sync_status = 'error'");
      final errorCount = (errRows.first['cnt'] as int?) ?? 0;
      final synced = rows.length - pendingLeft - errorCount;

      if (mounted) {
        // Show the ACTUAL error detail so user can diagnose.
        final msg = errorCount > 0
            ? 'Subidas $synced/${rows.length}. Fallaron $errorCount.\n${lastError ?? ''}'
            : 'Sincronización completa ($synced sesiones).';
        state = state.copyWith(
          status:         errorCount > 0 ? SyncStatus.error : SyncStatus.success,
          pendingCount:   pendingLeft + errorCount,
          lastSyncAt:     DateTime.now(),
          errorMessage:   errorCount > 0 ? msg : null,
          successMessage: errorCount == 0 ? msg : null,
        );
      }
    } catch (e) {
      if (mounted) {
        state = state.copyWith(
            status: SyncStatus.error,
            errorMessage: e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      _syncing = false;
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final syncProvider =
    StateNotifierProvider<SyncNotifier, SyncState>(
        (_) => SyncNotifier());
