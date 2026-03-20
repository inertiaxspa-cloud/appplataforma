import 'dart:async';
import 'package:usb_serial/usb_serial.dart';
import 'connection_datasource.dart';

/// Android USB OTG serial implementation.
/// Uses the `usb_serial` package (wraps Android USB Host API).
class AndroidUsbDataSource implements ConnectionDataSource {
  UsbPort? _port;
  StreamSubscription? _sub;
  final _lineController = StreamController<String>.broadcast();
  String _lineBuffer = '';
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
    final devices = await UsbSerial.listDevices();
    return devices.map((d) => ConnectionTarget(
      id: d.deviceName,
      displayName: '${d.manufacturerName ?? 'USB'} — ${d.productName ?? d.deviceName}',
      type: ConnectionType.androidUsb,
    )).toList();
  }

  @override
  Future<void> open(ConnectionTarget target) async {
    final devices = await UsbSerial.listDevices();
    final device = devices.firstWhere(
      (d) => d.deviceName == target.id,
      orElse: () => throw Exception('Device not found: ${target.id}'),
    );

    _port = await device.create();
    if (_port == null) throw Exception('Cannot create port for ${target.id}');

    final ok = await _port!.open();
    if (!ok) throw Exception('Cannot open ${target.id}');

    await _port!.setPortParameters(
      921600,
      UsbPort.DATABITS_8,
      UsbPort.STOPBITS_1,
      UsbPort.PARITY_NONE,
    );

    _sub = _port!.inputStream?.listen(_onData, onError: _onError);
    _connected     = true;
    _connectedName  = target.displayName;
  }

  void _onData(dynamic chunk) {
    final bytes = chunk as List<int>;
    _lineBuffer += String.fromCharCodes(bytes);
    while (_lineBuffer.contains('\n')) {
      final idx = _lineBuffer.indexOf('\n');
      final line = _lineBuffer.substring(0, idx).trim();
      _lineBuffer = _lineBuffer.substring(idx + 1);
      if (line.isNotEmpty) _lineController.add(line);
    }
  }

  void _onError(Object e) => _lineController.addError(e);

  @override
  Future<void> sendCommand(String command) async {
    await _port?.write(command.codeUnits.map((c) => c).toList() as dynamic);
  }

  @override
  Future<void> close() async {
    _connected = false;
    _connectedName = null;
    await _sub?.cancel();
    await _port?.close();
    _port = null;
    _lineBuffer = '';
    if (!_lineController.isClosed) await _lineController.close();
  }
}
