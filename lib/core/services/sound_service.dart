import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

/// Plays system beeps via Windows Kernel32 Beep().
/// All public calls are non-blocking — the tone runs in a background isolate
/// so the UI thread is never frozen.
/// On non-Windows platforms this is a silent no-op.
class SoundService {
  SoundService._();

  // ── Public sounds ──────────────────────────────────────────────────────────

  /// Short tick — each countdown second.
  static void countdown() => _fire([[700, 70]]);

  /// Higher tone — test is about to start.
  static void ready() => _fire([[1100, 180]]);

  /// Phase detected (takeoff, landing, IMTP onset…).
  static void phase() => _fire([[950, 90]]);

  /// Test completed — ascending 3-note melody.
  static void success() => _fire([[880, 90], [1047, 90], [1319, 220]]);

  /// Error or cancel — descending 2-note.
  static void error() => _fire([[600, 110], [440, 220]]);

  // ── Internal ───────────────────────────────────────────────────────────────

  static void _fire(List<List<int>> notes) {
    if (!Platform.isWindows) return;
    Isolate.run(() => _playNotes(notes));
  }

  static void _playNotes(List<List<int>> notes) {
    try {
      final lib  = DynamicLibrary.open('kernel32.dll');
      final beep = lib.lookupFunction<
          Bool Function(Uint32, Uint32),
          bool Function(int, int)>('Beep');
      for (final note in notes) {
        beep(note[0], note[1]);
      }
    } catch (e) {
      // Audio is non-critical — never crash the app.
      // ignore: avoid_print
      print('[Sound] Beep error: $e');
    }
  }
}
