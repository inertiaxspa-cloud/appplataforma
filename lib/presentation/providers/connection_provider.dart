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

  ConnectionNotifier(this._ds) : super(const ConnectionState());

  Future<void> refreshTargets() async {
    final targets = await _ds.listTargets();
    state = state.copyWith(availableTargets: targets, error: null);
  }

  Future<void> connect(ConnectionTarget target) async {
    try {
      await _ds.open(target);
      state = state.copyWith(
        isConnected: true,
        connectedName: target.displayName,
        error: null,
      );
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> disconnect() async {
    await _ds.close();
    state = state.copyWith(isConnected: false, connectedName: null);
  }
}

final connectionProvider =
    StateNotifierProvider<ConnectionNotifier, ConnectionState>((ref) {
  final ds = ref.watch(connectionDataSourceProvider);
  return ConnectionNotifier(ds);
});
