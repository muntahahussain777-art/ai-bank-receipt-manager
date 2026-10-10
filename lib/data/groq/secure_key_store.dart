import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Platform secure storage for Groq API secrets. Never use SQLite for keys.
abstract class SecureKeyStore {
  Future<void> write(String slot, String secret);
  Future<String?> read(String slot);
  Future<void> delete(String slot);
  Future<bool> contains(String slot);
}

class FlutterSecureKeyStore implements SecureKeyStore {
  FlutterSecureKeyStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(
              storageNamespace: 'ai_bank_receipt_manager_groq',
            ),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<void> write(String slot, String secret) =>
      _storage.write(key: slot, value: secret);

  @override
  Future<String?> read(String slot) => _storage.read(key: slot);

  @override
  Future<void> delete(String slot) => _storage.delete(key: slot);

  @override
  Future<bool> contains(String slot) async {
    final value = await _storage.read(key: slot);
    return value != null && value.isNotEmpty;
  }
}

/// In-memory store for unit tests. Does not touch the platform keystore.
class MemorySecureKeyStore implements SecureKeyStore {
  final Map<String, String> _values = {};

  @override
  Future<void> write(String slot, String secret) async {
    _values[slot] = secret;
  }

  @override
  Future<String?> read(String slot) async => _values[slot];

  @override
  Future<void> delete(String slot) async {
    _values.remove(slot);
  }

  @override
  Future<bool> contains(String slot) async =>
      _values[slot] != null && _values[slot]!.isNotEmpty;
}

/// Masks a secret for UI display. Never logs the full value.
String maskApiKey(String? secret) {
  if (secret == null || secret.isEmpty) {
    return '(empty)';
  }
  if (secret.length <= 8) {
    return '${secret[0]}***${secret[secret.length - 1]}';
  }
  return '${secret.substring(0, 4)}…${secret.substring(secret.length - 4)}';
}
