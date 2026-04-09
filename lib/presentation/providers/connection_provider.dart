import 'dart:async';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform, debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/utils/csv_parser.dart';
import '../../data/datasources/connection/connection_datasource.dart';
// Conditional imports: on web use lightweight stubs (dart:ffi unavailable)
import '../../data/datasources/connection/desktop_serial_datasource.dart'
    if (dart.library.html) '../../data/datasources/connection/web_stub_datasource.dart';
import '../../data/datasources/connection/android_usb_datasource.dart'
    if (dart.library.html) '../../data/datasources/connection/web_stub_datasource.dart';
import '../../data/datasources/connection/ble_connection_datasource.dart';
import '../../data/models/raw_sample.dart';
import '../../domain/dsp/signal_processor.dart';
import '../../domain/entities/calibration_data.dart';
import 'calibration_provider.dart';
import '../screens/settings/settings_screen.dart';

// ── Connection state ───────────────────────────────────────────────────────

class ConnectionState {
  final bool isConnected;
  final String? connectedName;
  final List<ConnectionTarget> availableTargets;
  final String? error;

  const ConnectionState({
    this.isConnected = false,
    this.connectedName,
    this.availableTargets = const [],
    this.error,
  });

  ConnectionState copyWith({
    bool? isConnected,
    String? connectedName,
    List<ConnectionTarget>? availableTargets,
    String? error,
  }) => ConnectionState(
    isConnected: isConnected ?? this.isConnected,
    connectedName: connectedName ?? this.connectedName,
    availableTargets: availableTargets ?? this.availableTargets,
    error: error,
  );
}

// ── Platform-aware data source ─────────────────────────────────────────────

final connectionDataSourceProvider = Provider<ConnectionDataSource>((ref) {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return AndroidUsbDataSource();
  }
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    return BleConnectionDataSource();
  }
  // Windows / macOS / Linux → real serial; web → no-op stub
  return DesktopSerialDataSource();
});

// ── Raw sample stream ──────────────────────────────────────────────────────

final rawSampleStreamProvider = StreamProvider<RawSample>((ref) {
  final ds = ref.watch(connectionDataSourceProvider);
  final parser = CsvParser();
  return ds.lineStream
      .map(parser.parse)
      .where((s) => s != null)
      .cast<RawSample>();
});

// ── Signal processor (stateful, uses calibration) ─────────────────────────

final signalProcessorProvider = Provider<SignalProcessor>((ref) {
  final cal = ref.watch(calibrationProvider).activeCalibration
      ?? CalibrationData.defaultCalibration();
  return SignalProcessor(cal);
});

// ── Connection notifier ────────────────────────────────────────────────────

class ConnectionNotifier extends StateNotifier<ConnectionState> {
  final ConnectionDataSource _ds;
  final Ref _ref;

  ConnectionNotifier(this._ds, this._ref) : super(const ConnectionState());

  Future<void> refreshTargets() async {
    final targets = await _ds.listTargets();
    state = state.copyWith(availableTargets: targets, error: null);
  }

  bool _connecting = false;

  /// Main connection flow: open → passive probe → retry with '1' → verify → finalize.
  /// Works for both firmware v2.3 (auto-stream) and legacy (A;0;L;R needs '1').
  ///
  /// Best cases:
  /// - v2.3: passive probe succeeds in ~200ms, zero '1' commands sent
  /// - legacy: first '1' retry succeeds in ~900ms
  ///
  /// Worst case: 4 retries over ~5.7s, then clean failure with diagnostic.
  Future<void> connect(ConnectionTarget target) async {
    if (_connecting || state.isConnected) return;
    _connecting = true;
    state = state.copyWith(error: null);
    final baudRate = _ref.read(settingsProvider).serialBaudRate;

    try {
      await _ds.open(target, baudRate: baudRate);

      // Phase 1: Passive probe — captures v2.3 firmware that auto-streams.
      debugPrint('[Connection] Phase 1: passive probe (700ms)');
      final passive = await _probeForSamples(timeoutMs: 700, requiredSamples: 5);
      if (passive.success) {
        debugPrint('[Connection] ✓ auto-stream detected (${passive.validSamples} samples)');
        _finalizeConnected(target);
        return;
      }

      // Phase 2: Legacy handshake — send '1', probe, retry up to 4 times.
      debugPrint('[Connection] Phase 2: legacy handshake (no passive samples)');
      _ProbeResult? lastResult = passive;
      for (int attempt = 1; attempt <= 4; attempt++) {
        await _ds.purgeInput();
        final sent = await _ds.sendCommand('1');
        if (!sent) {
          debugPrint('[Connection] sendCommand attempt $attempt failed, retrying...');
          await Future.delayed(const Duration(milliseconds: 200));
          continue;
        }

        final timeoutMs = 600 + attempt * 200; // 800, 1000, 1200, 1400
        final result = await _probeForSamples(
            timeoutMs: timeoutMs, requiredSamples: 5);
        debugPrint('[Connection] attempt $attempt: ${result.validSamples} valid, ${result.rawLines} raw');
        if (result.success) {
          debugPrint('[Connection] ✓ legacy firmware ready after $attempt attempts');
          _finalizeConnected(target);
          return;
        }
        lastResult = result;
        await Future.delayed(const Duration(milliseconds: 200));
      }

      // Phase 3: Give up with diagnostic message
      debugPrint('[Connection] ✗ All retries exhausted');
      await _tryCleanClose();
      state = state.copyWith(
        isConnected: false,
        connectedName: null,
        error: _buildDiagnosticMessage(lastResult),
      );
    } catch (e) {
      debugPrint('[Connection] Exception: $e');
      await _tryCleanClose();
      state = state.copyWith(error: e.toString());
    } finally {
      _connecting = false;
    }
  }

  void _finalizeConnected(ConnectionTarget target) {
    state = state.copyWith(
      isConnected: true,
      connectedName: target.displayName,
      error: null,
    );
    // Warm up the stream subscription so liveDataProvider receives data
    // without lazy-subscription gap. This must happen AFTER isConnected = true
    // so downstream observers are ready.
    try { _ref.read(rawSampleStreamProvider); } catch (_) {}
  }

  Future<void> _tryCleanClose() async {
    try { await _ds.close(); } catch (e) { debugPrint('[Connection] close error: $e'); }
  }

  /// Probes the lineStream for valid parseable samples within a time window.
  /// Returns success=true as soon as [requiredSamples] valid samples arrive,
  /// or on timeout with whatever count was achieved.
  Future<_ProbeResult> _probeForSamples({
    required int timeoutMs,
    required int requiredSamples,
  }) async {
    int validCount = 0;
    int rawLineCount = 0;
    final parser = CsvParser();
    final completer = Completer<_ProbeResult>();
    StreamSubscription<String>? sub;

    final timer = Timer(Duration(milliseconds: timeoutMs), () {
      if (!completer.isCompleted) {
        completer.complete(_ProbeResult(
          success: validCount >= requiredSamples,
          validSamples: validCount,
          rawLines: rawLineCount,
        ));
      }
    });

    sub = _ds.lineStream.listen(
      (line) {
        rawLineCount++;
        if (parser.parse(line) != null) validCount++;
        if (validCount >= requiredSamples && !completer.isCompleted) {
          completer.complete(_ProbeResult(
            success: true,
            validSamples: validCount,
            rawLines: rawLineCount,
          ));
        }
      },
      onError: (e) => debugPrint('[Connection] probe stream error: $e'),
    );

    try {
      return await completer.future;
    } finally {
      timer.cancel();
      await sub.cancel();
    }
  }

  String _buildDiagnosticMessage(_ProbeResult? last) {
    if (last == null || last.rawLines == 0) {
      return 'Sin datos recibidos. Verifica el cable USB y que la plataforma '
             'esté encendida. Si usas firmware legacy, revisa que responda al comando \'1\'.';
    }
    if (last.validSamples == 0) {
      return 'La plataforma envía datos pero no coinciden con el protocolo esperado. '
             'Verifica la versión del firmware (v2.3 o legacy A;0;L;R).';
    }
    return 'Conexión inestable: solo ${last.validSamples} muestras válidas de '
           '${last.rawLines} líneas. Prueba otro cable USB (más corto, blindado) '
           'o verifica la alimentación de la plataforma.';
  }

  // C7 fix: reset _connecting, wrap close in try-catch, clear error.
  Future<void> disconnect() async {
    _connecting = false;
    try { await _ds.sendCommand('0'); } catch (e) { debugPrint('[Connection] sendCommand(0) error: $e'); }
    try { await _ds.close(); } catch (e) { debugPrint('[Connection] close error: $e'); }
    state = state.copyWith(isConnected: false, connectedName: null, error: null);
  }
}

/// Result of a single probe pass.
class _ProbeResult {
  final bool success;
  final int validSamples;
  final int rawLines;
  const _ProbeResult({
    required this.success,
    required this.validSamples,
    required this.rawLines,
  });
}

final connectionProvider =
    StateNotifierProvider<ConnectionNotifier, ConnectionState>((ref) {
  final ds = ref.watch(connectionDataSourceProvider);
  return ConnectionNotifier(ds, ref);
});
