/// Abstract interface for all connection backends.
/// Implementations: Desktop serial, Android USB OTG, BLE (iOS).
abstract class ConnectionDataSource {
  /// Stream of complete CSV text lines (already stripped of \r\n).
  Stream<String> get lineStream;

  /// List of available connection targets (port name + description).
  Future<List<ConnectionTarget>> listTargets();

  /// Open a connection to [target].
  Future<void> open(ConnectionTarget target);

  /// Close the current connection.
  Future<void> close();

  /// Send a command string (e.g., '1' to start, '0' to stop streaming).
  Future<void> sendCommand(String command);

  bool get isConnected;
  String? get connectedTargetName;
}

class ConnectionTarget {
  final String id;          // port name or BLE address
  final String displayName; // human-readable description
  final ConnectionType type;

  const ConnectionTarget({
    required this.id,
    required this.displayName,
    required this.type,
  });
}

enum ConnectionType { serial, androidUsb, ble }
