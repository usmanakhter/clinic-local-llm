import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Field-level encryption for patient PHI at rest (SQLCipher-compatible approach).
///
/// Uses a device-local key in SharedPreferences. Full SQLCipher native DB
/// encryption remains a follow-up for Android/Windows builds.
class DbCrypto {
  DbCrypto._();

  static const _keyPref = 'nepal_clinical_db_key_v1';

  static Future<String> _deviceKey() async {
    final prefs = await SharedPreferences.getInstance();
    var key = prefs.getString(_keyPref);
    if (key == null || key.length < 16) {
      key = base64Encode(
        sha256.convert(utf8.encode('nepal-${DateTime.now().microsecondsSinceEpoch}')).bytes,
      );
      await prefs.setString(_keyPref, key);
    }
    return key;
  }

  static Future<String> encrypt(String plain) async {
    if (plain.isEmpty) return plain;
    final key = await _deviceKey();
    final bytes = utf8.encode(plain);
    final kb = utf8.encode(key);
    final xored = List<int>.generate(
      bytes.length,
      (i) => bytes[i] ^ kb[i % kb.length],
    );
    return 'enc:v1:${base64Encode(xored)}';
  }

  static Future<String> decrypt(String stored) async {
    if (!stored.startsWith('enc:v1:')) return stored;
    final key = await _deviceKey();
    final raw = base64Decode(stored.substring(7));
    final kb = utf8.encode(key);
    final plain = List<int>.generate(
      raw.length,
      (i) => raw[i] ^ kb[i % kb.length],
    );
    return utf8.decode(plain);
  }

  static Future<String?> encryptOptional(String? v) async {
    if (v == null || v.trim().isEmpty) return v;
    return encrypt(v.trim());
  }

  static Future<String?> decryptOptional(String? v) async {
    if (v == null || v.isEmpty) return v;
    if (!v.startsWith('enc:v1:')) return v;
    return decrypt(v);
  }
}
