import 'dart:async';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
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

  Future<void> connect(ConnectionTarget target) async {
    if (_connecting || state.isConnected) return; // prevenir doble conexión
    _connecting = true;
    final baudRate = _ref.read(settingsProvider).serialBaudRate;
    try {
      await _ds.open(target, baudRate: baudRate);
      // Send start-streaming command. The v2.3 firmware streams continuously
      // and ignores this; the legacy firmware (A;0;L;R format) requires it
      // to begin sending data.
      // Wait for ESP32 firmware to boot after DTR reset + reader to be active.
      await Future.delayed(const Duration(milliseconds: 500));
      await _ds.sendCommand('1');
      state = state.copyWith(
        isConnected: true,
        connectedName: target.displayName,
        error: null,
      );
    } catch (e) {
      state = state.copyWith(error: e.toString());
    } finally {
      _connecting = false;
    }
  }

  // C7 fix: reset _connecting, wrap close in try-catch, clear error.
  Future<void> disconnect() async {
    _connecting = false;
    try { await _ds.sendCommand('0'); } catch (_) {}
    try { await _ds.close(); } catch (_) {}
    state = state.copyWith(isConnected: false, connectedName: null, error: null);
  }
}

final connectionProvider =
    StateNotifierProvider<ConnectionNotifier, ConnectionState>((ref) {
  final ds = ref.watch(connectionDataSourceProvider);
  return ConnectionNotifier(ds, ref);
});
