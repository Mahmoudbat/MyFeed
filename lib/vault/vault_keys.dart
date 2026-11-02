import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Thrown by [VaultKeyHeader.unwrap] when the password is wrong.
class WrongPasswordException implements Exception {
  @override
  String toString() => 'WrongPasswordException';
}

/// On-disk description of how the vault's data-encryption key (DEK) is
/// protected.
///
/// The DEK is 32 random bytes. It is never stored in the clear: it is
/// encrypted ("wrapped") with AES-256-GCM under a key-encryption key derived
/// from the user's password with PBKDF2-HMAC-SHA256 and a random salt.
/// A successful GCM unwrap is also the password check, so neither the
/// password nor a hash of it is stored anywhere.
class VaultKeyHeader {
  VaultKeyHeader({
    required this.iterations,
    required this.salt,
    required this.wrappedKey,
  });

  /// OWASP (2023) recommendation for PBKDF2-HMAC-SHA256.
  static const int defaultIterations = 600000;
  static const int formatVersion = 2;

  final int iterations;
  final List<int> salt;

  /// nonce(12) | ciphertext(32) | tag(16)
  final List<int> wrappedKey;

  static AesGcm get _aes => Cryptography.instance.aesGcm(secretKeyLength: 32);

  static List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }

  static Future<SecretKey> _deriveKek(String password, List<int> salt, int iterations) {
    final pbkdf2 = Cryptography.instance.pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
    return pbkdf2.deriveKeyFromPassword(password: password, nonce: salt);
  }

  static Future<VaultKeyHeader> _wrap(
    SecretKey dek,
    String password,
    int iterations,
  ) async {
    final salt = _randomBytes(16);
    final kek = await _deriveKek(password, salt, iterations);
    final aes = _aes;
    final box = await aes.encrypt(
      await dek.extractBytes(),
      secretKey: kek,
      nonce: aes.newNonce(),
      aad: utf8.encode('myfeed-vault-dek-v$formatVersion'),
    );
    return VaultKeyHeader(
      iterations: iterations,
      salt: salt,
      wrappedKey: box.concatenation(),
    );
  }

  /// Creates a fresh random DEK protected by [password].
  static Future<(VaultKeyHeader, SecretKey)> create(
    String password, {
    int iterations = defaultIterations,
  }) async {
    final dek = SecretKey(_randomBytes(32));
    return (await _wrap(dek, password, iterations), dek);
  }

  /// Re-wraps an existing DEK under a new password (no file re-encryption).
  static Future<VaultKeyHeader> rewrap(
    SecretKey dek,
    String newPassword, {
    int iterations = defaultIterations,
  }) =>
      _wrap(dek, newPassword, iterations);

  /// Returns the DEK, or throws [WrongPasswordException].
  Future<SecretKey> unwrap(String password) async {
    final kek = await _deriveKek(password, salt, iterations);
    final box = SecretBox.fromConcatenation(
      wrappedKey,
      nonceLength: 12,
      macLength: 16,
    );
    try {
      final bytes = await _aes.decrypt(
        box,
        secretKey: kek,
        aad: utf8.encode('myfeed-vault-dek-v$formatVersion'),
      );
      return SecretKey(Uint8List.fromList(bytes));
    } on SecretBoxAuthenticationError {
      throw WrongPasswordException();
    }
  }

  Map<String, Object> toJson() => {
        'v': formatVersion,
        'kdf': 'pbkdf2-hmac-sha256',
        'iterations': iterations,
        'salt': base64Encode(salt),
        'wrappedKey': base64Encode(wrappedKey),
      };

  factory VaultKeyHeader.fromJson(Map<String, dynamic> json) {
    if (json['v'] != formatVersion || json['kdf'] != 'pbkdf2-hmac-sha256') {
      throw const FormatException('unsupported vault header');
    }
    return VaultKeyHeader(
      iterations: json['iterations'] as int,
      salt: base64Decode(json['salt'] as String),
      wrappedKey: base64Decode(json['wrappedKey'] as String),
    );
  }
}
