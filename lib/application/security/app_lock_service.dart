import 'dart:convert';
import 'dart:math';

import 'package:ai_bank_receipt_manager/data/utils/hashing.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Optional PIN / biometric gate. PIN hash never leaves secure storage.
class AppLockService {
  AppLockService({
    FlutterSecureStorage? storage,
    LocalAuthentication? localAuth,
  }) : _storage = storage ?? const FlutterSecureStorage(),
       _localAuth = localAuth ?? LocalAuthentication();

  static const _pinHashKey = 'app_lock_pin_hash_v1';
  static const _pinSaltKey = 'app_lock_pin_salt_v1';
  static const _enabledKey = 'app_lock_enabled_v1';
  static const _biometricKey = 'app_lock_biometric_v1';

  final FlutterSecureStorage _storage;
  final LocalAuthentication _localAuth;

  Future<bool> isEnabled() async {
    try {
      return (await _storage.read(key: _enabledKey)) == '1';
    } catch (_) {
      return false;
    }
  }

  Future<bool> biometricEnabled() async {
    try {
      return (await _storage.read(key: _biometricKey)) == '1';
    } catch (_) {
      return false;
    }
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    await _storage.write(key: _biometricKey, value: enabled ? '1' : '0');
  }

  Future<void> enableWithPin(String pin) async {
    if (pin.length < 4 || pin.length > 12 || int.tryParse(pin) == null) {
      throw StateError('PIN must be 4-12 digits.');
    }
    final random = Random.secure();
    final saltBytes = List<int>.generate(16, (_) => random.nextInt(256));
    final saltB64 = base64Encode(saltBytes);
    final hash = sha256HexOfString('$saltB64:$pin');
    await _storage.write(key: _pinSaltKey, value: saltB64);
    await _storage.write(key: _pinHashKey, value: hash);
    await _storage.write(key: _enabledKey, value: '1');
  }

  Future<void> disable({required String currentPin}) async {
    if (!await verifyPin(currentPin)) {
      throw StateError('Current PIN is incorrect.');
    }
    await _storage.delete(key: _pinHashKey);
    await _storage.delete(key: _pinSaltKey);
    await _storage.write(key: _enabledKey, value: '0');
    await _storage.write(key: _biometricKey, value: '0');
  }

  Future<bool> verifyPin(String pin) async {
    final salt = await _storage.read(key: _pinSaltKey);
    final expected = await _storage.read(key: _pinHashKey);
    if (salt == null || expected == null) {
      return false;
    }
    return sha256HexOfString('$salt:$pin') == expected;
  }

  Future<bool> canCheckBiometrics() async {
    try {
      return await _localAuth.canCheckBiometrics ||
          await _localAuth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Future<bool> unlockWithBiometrics() async {
    if (!await biometricEnabled()) {
      return false;
    }
    try {
      return await _localAuth.authenticate(
        localizedReason: 'Unlock AI Bank Receipt Manager',
        biometricOnly: true,
      );
    } catch (_) {
      return false;
    }
  }
}
