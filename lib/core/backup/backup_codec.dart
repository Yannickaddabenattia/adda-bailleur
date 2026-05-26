import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

/// Format de fichier de sauvegarde chiffré ADDA Bailleur.
///
/// ```
/// bytes 0..3    : magic "ADLB"
/// byte  4       : version (1)
/// bytes 5..20   : salt (16 octets)
/// bytes 21..32  : nonce (12 octets)
/// bytes 33..n   : ciphertext || GCM tag (16 octets finaux)
/// ```
///
/// Dérivation de clé : PBKDF2-HMAC-SHA256, 200 000 itérations, clé de 32 octets.
/// Chiffrement : AES-256-GCM.
class BackupCodec {
  static const _magic = [0x41, 0x44, 0x4C, 0x42]; // "ADLB"
  static const int _version = 1;
  static const int _saltLen = 16;
  static const int _nonceLen = 12;
  static const int _keyLen = 32;
  static const int _pbkdf2Iterations = 200000;

  /// Variante non-bloquante : exécute [encrypt] dans un isolate via
  /// `compute` pour ne pas geler l'UI pendant le PBKDF2 (≈200 000 iter).
  static Future<Uint8List> encryptAsync({
    required String jsonPayload,
    required String passphrase,
  }) {
    return compute(_encryptIsolate, (jsonPayload, passphrase));
  }

  /// Variante non-bloquante : exécute [decrypt] dans un isolate.
  static Future<String> decryptAsync({
    required Uint8List bytes,
    required String passphrase,
  }) {
    return compute(_decryptIsolate, (bytes, passphrase));
  }

  /// Chiffre un payload JSON avec une passphrase.
  static Uint8List encrypt({
    required String jsonPayload,
    required String passphrase,
  }) {
    final salt = _randomBytes(_saltLen);
    final nonce = _randomBytes(_nonceLen);
    final key = _deriveKey(passphrase, salt);

    final gcm = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)),
      );
    final plaintext = Uint8List.fromList(utf8.encode(jsonPayload));
    final ciphertext = gcm.process(plaintext);

    final builder = BytesBuilder()
      ..add(_magic)
      ..addByte(_version)
      ..add(salt)
      ..add(nonce)
      ..add(ciphertext);
    return builder.toBytes();
  }

  /// Déchiffre une sauvegarde. Lève [BackupFormatException] si le format est
  /// invalide ou [BackupDecryptionException] si la passphrase est incorrecte.
  static String decrypt({
    required Uint8List bytes,
    required String passphrase,
  }) {
    if (bytes.length < 4 + 1 + _saltLen + _nonceLen + 16) {
      throw const BackupFormatException('Fichier trop court');
    }
    for (var i = 0; i < 4; i++) {
      if (bytes[i] != _magic[i]) {
        throw const BackupFormatException('Magic invalide');
      }
    }
    if (bytes[4] != _version) {
      throw BackupFormatException('Version non supportée: ${bytes[4]}');
    }
    final salt = bytes.sublist(5, 5 + _saltLen);
    final nonce = bytes.sublist(5 + _saltLen, 5 + _saltLen + _nonceLen);
    final ciphertext = bytes.sublist(5 + _saltLen + _nonceLen);

    final key = _deriveKey(passphrase, salt);
    final gcm = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)),
      );
    try {
      final plaintext = gcm.process(ciphertext);
      return utf8.decode(plaintext);
    } on InvalidCipherTextException {
      throw const BackupDecryptionException('Passphrase incorrecte');
    }
  }

  static Uint8List _deriveKey(String passphrase, Uint8List salt) {
    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, _pbkdf2Iterations, _keyLen));
    return pbkdf2.process(Uint8List.fromList(utf8.encode(passphrase)));
  }

  static Uint8List _randomBytes(int length) {
    final rnd = Random.secure();
    final out = Uint8List(length);
    for (var i = 0; i < length; i++) {
      out[i] = rnd.nextInt(256);
    }
    return out;
  }
}

Uint8List _encryptIsolate((String, String) args) =>
    BackupCodec.encrypt(jsonPayload: args.$1, passphrase: args.$2);

String _decryptIsolate((Uint8List, String) args) =>
    BackupCodec.decrypt(bytes: args.$1, passphrase: args.$2);

class BackupFormatException implements Exception {
  final String message;
  const BackupFormatException(this.message);
  @override
  String toString() => 'BackupFormatException: $message';
}

class BackupDecryptionException implements Exception {
  final String message;
  const BackupDecryptionException(this.message);
  @override
  String toString() => 'BackupDecryptionException: $message';
}
