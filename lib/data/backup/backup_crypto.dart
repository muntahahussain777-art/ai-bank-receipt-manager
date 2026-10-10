import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Authenticated encryption for sensitive backups (AES-256-GCM + PBKDF2).
class BackupCrypto {
  BackupCrypto({this.iterations = 120000});

  final int iterations;
  static const formatId = 'aibr-encrypted-v1';

  Future<Uint8List> encryptZip({
    required Uint8List zipBytes,
    required String password,
    Map<String, Object?>? manifestPreview,
  }) async {
    if (password.trim().length < 6) {
      throw StateError('Backup password must be at least 6 characters.');
    }
    final algorithm = AesGcm.with256bits();
    final random = Random.secure();
    final salt = Uint8List.fromList(
      List<int>.generate(16, (_) => random.nextInt(256)),
    );
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
    final secretKey = await pbkdf2.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
    final nonce = algorithm.newNonce();
    final secretBox = await algorithm.encrypt(
      zipBytes,
      secretKey: secretKey,
      nonce: nonce,
    );
    final envelope = <String, Object?>{
      'format': formatId,
      'kdf': 'pbkdf2-hmac-sha256',
      'iterations': iterations,
      'salt': base64Encode(salt),
      'nonce': base64Encode(nonce),
      'cipher': 'aes-256-gcm',
      'mac': base64Encode(secretBox.mac.bytes),
      'ciphertext': base64Encode(secretBox.cipherText),
      'includesApiKeys': false,
      'manifestPreview': ?manifestPreview,
    };
    return Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(envelope)),
    );
  }

  Future<Uint8List> decryptToZip({
    required Uint8List envelopeBytes,
    required String password,
  }) async {
    final decoded = jsonDecode(utf8.decode(envelopeBytes));
    if (decoded is! Map) {
      throw StateError('Encrypted backup envelope is invalid.');
    }
    final map = Map<String, Object?>.from(decoded);
    if (map['format'] != formatId) {
      throw StateError('Unsupported encrypted backup format.');
    }
    final salt = base64Decode(map['salt']! as String);
    final nonce = base64Decode(map['nonce']! as String);
    final mac = base64Decode(map['mac']! as String);
    final cipherText = base64Decode(map['ciphertext']! as String);
    final iter = (map['iterations'] as num?)?.toInt() ?? iterations;

    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iter,
      bits: 256,
    );
    final secretKey = await pbkdf2.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
    final algorithm = AesGcm.with256bits();
    try {
      final clear = await algorithm.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
        secretKey: secretKey,
      );
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      throw StateError('Wrong backup password or corrupt encrypted archive.');
    }
  }

  static bool looksEncrypted(List<int> bytes) {
    if (bytes.length < 32) {
      return false;
    }
    final head = utf8.decode(bytes.take(64).toList(), allowMalformed: true);
    return head.contains(formatId);
  }
}
