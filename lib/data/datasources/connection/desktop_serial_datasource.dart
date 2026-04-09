import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'connection_datasource.dart';

/// USB Serial implementation for Windows, macOS, Linux.
/// Uses flutter_libserialport.
class DesktopSerialDataSource implements ConnectionDataSource {
  SerialPort? _port;
  SerialPortReader? _reader;
  final _lineController = StreamController<String>.broadcast();
  Uint8List _buffer = Uint8List(0);
  bool _connected = false;
  String? _connectedName;

  @override
  Stream<String> get lineStream => _lineController.stream;

  @override
  bool get isConnected => _connected;

  @override
  String? get connectedTargetName => _connectedName;

  @override
  Future<List<ConnectionTarget>> listTargets() async {
    return SerialPort.availablePorts.map((portName) {
      final port = SerialPort(portName);
      final desc = port.description ?? portName;
      port.dispose();
      return ConnectionTarget(
        id: portName,
        displayName: '$portName — $desc',
        type: ConnectionType.serial,
      );
    }).toList();
  }

  @override
  Future<void> open(ConnectionTarget target, {int baudRate = 921600}) async {
    _port = SerialPort(target.id);

    if (!_port!.openReadWrite()) {
      final err = SerialPort.lastError?.toString() ?? 'Unknown error';
      throw Exception(
        'Cannot open ${target.id}: $err\n'
        'Make sure Arduino IDE, serial monitors, or other apps are closed.',
      );
    }

    final configOn = SerialPortConfig()
      ..baudRate = baudRate
      ..bits     = 8
      ..stopBits = 1
      ..parity   = SerialPortParity.none
      ..dtr      = SerialPortDtr.on
      ..rts      = SerialPortRts.on;
    _port!.config = configOn;

    // CRITICAL: attach reader listener BEFORE the DTR reset pulse.
    // This way bootloader bytes flow through _onData → parser → filtered.
    // There is no window during which bytes can be lost.
    _reader = SerialPortReader(_port!);
    _reader!.stream.listen(_onData, onError: _onError, cancelOnError: false);

    // Pulse DTR to reset ESP32 — same as Arduino IDE Serial Monitor.
    // DTR → EN pin via RC circuit on most ESP32 boards.
    final configOff = SerialPortConfig()
      ..baudRate = baudRate
      ..bits     = 8
      ..stopBits = 1
      ..parity   = SerialPortParity.none
      ..dtr      = SerialPortDtr.off
      ..rts      = SerialPortRts.on;
    _port!.config = configOff;
    await Future.delayed(const Duration(milliseconds: 50));
    _port!.config = configOn; // DTR back ON → ESP32 resets

    _connected     = true;
    _connectedName = target.displayName;
    // Note: no blind wait here. The ConnectionNotifier probe loop handles
    // timing based on actual observed data, not hardcoded delays.
  }

  void _onData(Uint8List chunk) {
    // Safety cap: discard buffer if it grows beyond 64 KB without a newline
    // (indicates corrupt/stuck firmware — prevents unbounded memory growth).
    if (_buffer.length > 65536) _buffer = Uint8List(0);

    _buffer = Uint8List.fromList([..._buffer, ...chunk]);
    while (true) {
      final nl = _buffer.indexOf(0x0A); // '\n'
      if (nl < 0) break;
      final lineBytes = _buffer.sublist(0, nl);
      _buffer = _buffer.sublist(nl + 1);
      final line = utf8.decode(lineBytes, allowMalformed: true).trim();
      if (line.isNotEmpty) _lineController.add(line);
    }
  }

  void _onError(Object e) {
    _lineController.addError(e);
  }

  @override
  Future<bool> sendCommand(String command) async {
    if (_port == null || !_connected) return false;
    try {
      final bytes = Uint8List.fromList(ascii.encode(command));
      final written = _port!.write(bytes);
      if (written != bytes.length) return false;
      // Force OS-level output buffer flush so the byte actually hits the wire
      // before this future completes. Without this, the 'true' return value
      // could be a lie (byte is still in the kernel buffer).
      try { _port!.flush(); } catch (_) {}
      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<void> purgeInput() async {
    try {
      _port?.flush(SerialPortBuffer.input);
    } catch (_) {}
    _buffer = Uint8List(0);
  }

  @override
  Future<void> close() async {
    _connected = false;
    _connectedName = null;
    _reader?.close();
    _port?.close();
    _port?.dispose();
    _port = null;
    _reader = null;
    _buffer = Uint8List(0);
    // NOTE: Do NOT close _lineController here — it needs to survive
    // reconnection cycles. Listeners (rawSampleStreamProvider) hold
    // references to this stream and would lose data on reconnect.
  }
}
