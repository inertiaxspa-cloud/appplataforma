/// Desktop (Windows / macOS / Linux) FFI initialisation for sqflite.
/// Imported only on non-web platforms.

import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Call once before opening a database.
/// On desktop it switches sqflite to the FFI factory; on mobile it's a no-op.
void initSqfliteForPlatform() {
  if (defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
}
