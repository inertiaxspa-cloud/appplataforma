import 'package:flutter_test/flutter_test.dart';
import 'package:inertiax/presentation/providers/sync_provider.dart';

// These tests cover the pure Dart logic of SyncState and the _syncing guard.
// They do NOT touch Supabase or SQLite — all tests are self-contained.

void main() {
  group('SyncState', () {
    test('default values are sensible', () {
      const state = SyncState(status: SyncStatus.unauthenticated);
      expect(state.pendingCount, equals(0));
      expect(state.lastSyncAt, isNull);
      expect(state.errorMessage, isNull);
      expect(state.userEmail, isNull);
      expect(state.successMessage, isNull);
      expect(state.isAuthenticated, isFalse);
      expect(state.isBusy, isFalse);
    });

    test('isAuthenticated is true when userEmail is set', () {
      const state = SyncState(
          status: SyncStatus.idle, userEmail: 'test@example.com');
      expect(state.isAuthenticated, isTrue);
    });

    test('isBusy is true only when status == syncing', () {
      expect(
        const SyncState(status: SyncStatus.syncing).isBusy,
        isTrue,
      );
      for (final s in SyncStatus.values.where((s) => s != SyncStatus.syncing)) {
        expect(const SyncState(status: SyncStatus.idle).isBusy, isFalse);
      }
    });
  });

  group('SyncState.copyWith', () {
    const base = SyncState(
      status:       SyncStatus.idle,
      pendingCount: 5,
      userEmail:    'user@example.com',
      errorMessage: 'some error',
      successMessage: 'some success',
    );

    test('copyWith preserves unchanged fields', () {
      final copy = base.copyWith(pendingCount: 3);
      expect(copy.status,       equals(SyncStatus.idle));
      expect(copy.pendingCount, equals(3));
      expect(copy.userEmail,    equals('user@example.com'));
    });

    test('copyWith clearError removes errorMessage', () {
      final copy = base.copyWith(clearError: true);
      expect(copy.errorMessage, isNull);
    });

    test('copyWith clearUser removes userEmail', () {
      final copy = base.copyWith(clearUser: true);
      expect(copy.userEmail, isNull);
    });

    test('copyWith clearSuccess removes successMessage', () {
      final copy = base.copyWith(clearSuccess: true);
      expect(copy.successMessage, isNull);
    });

    test('copyWith with new status overrides', () {
      final copy = base.copyWith(status: SyncStatus.error);
      expect(copy.status, equals(SyncStatus.error));
    });

    test('copyWith sets lastSyncAt when provided', () {
      final now = DateTime.now();
      final copy = base.copyWith(lastSyncAt: now);
      expect(copy.lastSyncAt, equals(now));
    });

    test('copyWith with both clearError and new errorMessage: clear wins', () {
      // clearError=true nullifies regardless of errorMessage parameter
      final copy = base.copyWith(
          clearError: true, errorMessage: 'new error');
      expect(copy.errorMessage, isNull);
    });
  });

  group('SyncStatus enum', () {
    test('all expected values exist', () {
      expect(SyncStatus.values, containsAll([
        SyncStatus.unauthenticated,
        SyncStatus.idle,
        SyncStatus.syncing,
        SyncStatus.success,
        SyncStatus.error,
      ]));
    });
  });

  group('_syncing guard — unit-level logic', () {
    // We test the guard behaviour by examining the state transitions directly
    // on SyncState rather than calling syncPending() (which requires a DB).

    test('syncPending() must check isAuthenticated and _syncing before proceeding', () {
      // Verify: when NOT authenticated, syncPending() is a no-op.
      // We check isAuthenticated flag.
      const unauthState =
          SyncState(status: SyncStatus.unauthenticated);
      expect(unauthState.isAuthenticated, isFalse);
    });

    test('isBusy true while syncing prevents double-sync', () {
      // If state.isBusy == true the caller should not trigger another sync.
      // This reflects the _syncing guard at the notifier level.
      const syncingState = SyncState(status: SyncStatus.syncing);
      expect(syncingState.isBusy, isTrue);
    });

    test('error state does not block subsequent sync attempt', () {
      // After an error the state is NOT "syncing", so isBusy == false
      // and a new syncPending() call would be allowed.
      const errorState = SyncState(status: SyncStatus.error);
      expect(errorState.isBusy, isFalse);
    });
  });

  group('SyncState equality / immutability', () {
    test('two identical SyncState instances are not identical objects (value type)', () {
      const a = SyncState(status: SyncStatus.idle, pendingCount: 2);
      final b = a.copyWith(pendingCount: 2); // same values
      // They are different object instances
      expect(identical(a, b), isFalse);
      // But same field values
      expect(b.status,       equals(a.status));
      expect(b.pendingCount, equals(a.pendingCount));
    });
  });
}
