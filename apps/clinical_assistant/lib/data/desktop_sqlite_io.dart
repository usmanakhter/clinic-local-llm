import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Initializes sqflite FFI on Linux/Windows desktop (no native sqflite plugin).
void initDesktopSqlite() {
  if (Platform.isLinux || Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
}
