/// Web stubs for serial/USB datasources.
///
/// flutter_libserialport and usb_serial both use dart:ffi which is not
/// available on the web platform. These stubs satisfy the import and return
/// sensible "not supported" values so the UI can still run in a browser.

import 'connection_datasource.dart';

/// Web stub — no serial port access in the browser.
class DesktopSerialDataSource implements ConnectionDataSource {
  @override
  Stream<String> get lineStream => const Stream.empty();

  @override
  Future<List<ConnectionTarget>> listTargets() async => [];

  @override
  Future<void> open(ConnectionTarget target, {int baudRate = 921600}) async {
    throw UnsupportedError('Serial port not available on web');
  }

  @override
  Future<void> close() async {}

  @override
  Future<bool> sendCommand(String command) async => false;

  @override
  Future<void> purgeInput() async {}

  @override
  bool get isConnected => false;

  @override
  String? get connectedTargetName => null;
}

/// Web stub — no USB OTG in the browser.
class AndroidUsbDataSource implements ConnectionDataSource {
  @override
  Stream<String> get lineStream => const Stream.empty();

  @override
  Future<List<ConnectionTarget>> listTargets() async => [];

  @override
  Future<void> open(ConnectionTarget target, {int baudRate = 921600}) async {
    throw UnsupportedError('USB serial not available on web');
  }

  @override
  Future<void> close() async {}

  @override
  Future<bool> sendCommand(String command) async => false;

  @override
  Future<void> purgeInput() async {}

  @override
  bool get isConnected => false;

  @override
  String? get connectedTargetName => null;
}
