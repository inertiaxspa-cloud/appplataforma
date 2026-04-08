import 'dart:async' show StreamController, StreamSubscription;
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'connection_datasource.dart';

// Nordic UART Service (NUS) — commonly used for BLE serial tunneling.
// If the firmware uses a different service/characteristic UUID, update below.
const _nusServiceUuid        = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
const _nusRxCharUuid         = '6e400002-b5a3-f393-e0a9-e50e24dcca9e'; // write
const _nusNotifyCharUuid     = '6e400003-b5a3-f393-e0a9-e50e24dcca9e'; // notify
const _scanTimeoutSeconds    = 10;

/// BLE datasource for iOS (and Android as fallback).
/// Implements the Nordic UART Service tunnel to receive CSV lines.
class BleConnectionDataSource implements ConnectionDataSource {
  final _lineController   = StreamController<String>.broadcast();
  final _buffer           = StringBuffer();
  BluetoothDevice?        _device;
  StreamSubscription?     _notifySub;
  StreamSubscription?     _scanSub;

  @override
  Stream<String> get lineStream => _lineController.stream;

  @override
  bool get isConnected => _device != null;

  @override
  String? get connectedTargetName => _device?.platformName;

  // ── Discover ──────────────────────────────────────────────────────────────

  @override
  Future<List<ConnectionTarget>> listTargets() async {
    final found = <ConnectionTarget>[];

    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: _scanTimeoutSeconds),
    );

    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final name = r.device.platformName;
        if (name.toLowerCase().contains('inertia') ||
            name.toLowerCase().contains('inertiax') ||
            name.toLowerCase().contains('force')) {
          final target = ConnectionTarget(
            id:          r.device.remoteId.str,
            displayName: name.isNotEmpty ? name : r.device.remoteId.str,
            type:        ConnectionType.ble,
          );
          if (!found.any((t) => t.id == target.id)) {
            found.add(target);
          }
        }
      }
    });

    await Future.delayed(const Duration(seconds: _scanTimeoutSeconds));
    await FlutterBluePlus.stopScan();
    _scanSub?.cancel();

    // If none matched by name, return all found devices so user can pick
    if (found.isEmpty) {
      final all = FlutterBluePlus.lastScanResults;
      for (final r in all) {
        found.add(ConnectionTarget(
          id:          r.device.remoteId.str,
          displayName: r.device.platformName.isNotEmpty
              ? r.device.platformName
              : r.device.remoteId.str,
          type:        ConnectionType.ble,
        ));
      }
    }

    return found;
  }

  // ── Connect ───────────────────────────────────────────────────────────────

  @override
  Future<void> open(ConnectionTarget target, {int baudRate = 921600}) async {
    _device = BluetoothDevice.fromId(target.id);

    await _device!.connect(
      timeout: const Duration(seconds: 15),
      autoConnect: false,
    );

    // Discover services
    final services = await _device!.discoverServices();
    BluetoothCharacteristic? notifyChar;

    for (final s in services) {
      if (s.uuid.toString().toLowerCase() == _nusServiceUuid) {
        for (final c in s.characteristics) {
          final uuid = c.uuid.toString().toLowerCase();
          if (uuid == _nusNotifyCharUuid) notifyChar = c;
        }
      }
    }

    if (notifyChar == null) {
      throw Exception('Nordic UART Notify characteristic not found. '
          'Check firmware BLE service UUID.');
    }

    // Subscribe to notifications
    await notifyChar.setNotifyValue(true);
    _notifySub = notifyChar.lastValueStream.listen(_onChunk);
  }

  // ── Disconnect ────────────────────────────────────────────────────────────

  @override
  Future<void> close() async {
    await _notifySub?.cancel();
    _notifySub = null;
    try {
      await _device?.disconnect();
    } catch (e) { assert(() { print('[BLE] disconnect error: $e'); return true; }()); }
    _device  = null;
    _buffer.clear();
    if (!_lineController.isClosed) await _lineController.close();
  }

  // ── Send command ──────────────────────────────────────────────────────────

  @override
  Future<void> sendCommand(String cmd) async {
    if (_device == null) return;
    final services = await _device!.discoverServices();
    for (final s in services) {
      if (s.uuid.toString().toLowerCase() == _nusServiceUuid) {
        for (final c in s.characteristics) {
          if (c.uuid.toString().toLowerCase() == _nusRxCharUuid) {
            await c.write(utf8.encode('$cmd\n'), withoutResponse: false);
            return;
          }
        }
      }
    }
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  void _onChunk(List<int> bytes) {
    final chunk = utf8.decode(bytes, allowMalformed: true);
    _buffer.write(chunk);
    final buf = _buffer.toString();
    final lines = buf.split('\n');
    // Keep the last (possibly incomplete) fragment in buffer
    _buffer
      ..clear()
      ..write(lines.last);
    for (var i = 0; i < lines.length - 1; i++) {
      final line = lines[i].trim();
      if (line.isNotEmpty) _lineController.add(line);
    }
  }
}
