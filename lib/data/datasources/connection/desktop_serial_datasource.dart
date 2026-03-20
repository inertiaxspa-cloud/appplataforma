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
  Future<void> open(ConnectionTarget target) async {
    _port = SerialPort(target.id);

    final config = SerialPortConfig()
      ..baudRate = 921600
      ..bits     = 8
      ..stopBits = 1
      ..parity   = SerialPortParity.none;

    if (!_port!.openReadWrite()) {
      throw Exception('Cannot open ${target.id}: ${SerialPort.lastError}');
    }
    _port!.config = config;

    _reader = SerialPortReader(_port!);
    _reader!.stream.listen(_onData, onError: _onError, cancelOnError: false);

    _connected    = true;
    _connectedName = target.displayName;
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
  Future<void> sendCommand(String command) async {
    if (_port == null || !_connected) return;
    final bytes = ascii.encode(command);
    _port!.write(Uint8List.fromList(bytes));
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
    if (!_lineController.isClosed) await _lineController.close();
  }
}
