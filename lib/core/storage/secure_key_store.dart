import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../constants.dart';

/// Gère la clé de chiffrement AES-256 utilisée par Hive.
///
/// La clé est générée une seule fois à la première exécution puis stockée
/// dans le gestionnaire sécurisé de la plateforme :
/// - iOS / macOS : Keychain
/// - Android : Keystore
/// - Linux : libsecret (GNOME Keyring / KWallet)
class SecureKeyStore {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    mOptions: MacOsOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
      useDataProtectionKeyChain: false,
    ),
  );

  /// Retourne la clé de chiffrement Hive (32 octets, AES-256).
  /// La crée si elle n'existe pas encore.
  ///
  /// Si le coffre sécurisé est corrompu (BAD_DECRYPT après un reset Keystore
  /// ou une mise à jour OS qui invalide la master key), on purge l'ensemble
  /// puis on regénère — les données Hive chiffrées avec l'ancienne clé sont
  /// alors inaccessibles de toute façon, l'utilisateur doit réimporter un
  /// backup `.adlb`.
  static Future<List<int>> getOrCreateEncryptionKey() async {
    try {
      final existing =
          await _storage.read(key: AppConstants.encryptionKeyAlias);
      if (existing != null) {
        return base64Decode(existing);
      }
    } on PlatformException {
      try {
        await _storage.deleteAll();
      } catch (_) {}
    }
    final key = _generateRandomKey(32);
    await _storage.write(
      key: AppConstants.encryptionKeyAlias,
      value: base64Encode(key),
    );
    return key;
  }

  /// Supprime la clé — utilisé lors d'un reset complet.
  static Future<void> deleteKey() async {
    await _storage.delete(key: AppConstants.encryptionKeyAlias);
  }

  static List<int> _generateRandomKey(int length) {
    final rng = Random.secure();
    return List<int>.generate(length, (_) => rng.nextInt(256));
  }
}
