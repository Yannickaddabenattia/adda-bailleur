import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart';

import '../core/storage/local_database.dart';

/// Calcul Argon2id `(motDePasse, sel) → 32 octets`. Fonction top-level pour
/// pouvoir l'exécuter dans un isolate via `compute` (Argon2 ~12 MiB est lourd
/// et gèlerait l'UI). Paramètres : Argon2id, 3 itérations, 12 MiB, 1 voie.
Uint8List _argon2idJob((String, Uint8List) job) {
  final (password, salt) = job;
  final params = Argon2Parameters(
    Argon2Parameters.ARGON2_id,
    salt,
    desiredKeyLength: 32,
    iterations: 3,
    memory: 12288, // KiB = 12 MiB
    lanes: 1,
    version: Argon2Parameters.ARGON2_VERSION_13,
  );
  final gen = Argon2BytesGenerator()..init(params);
  return gen.process(Uint8List.fromList(utf8.encode(password)));
}

/// Gère le **mot de passe maître** de l'utilisateur :
/// - un *vérificateur* Argon2id (sel + hash) est stocké localement (Hive)
///   pour confirmer le mot de passe sans avoir à déchiffrer une sauvegarde ;
/// - le mot de passe lui-même est mémorisé dans le trousseau sécurisé de
///   l'OS, afin que la sauvegarde chiffrée puisse tourner sans ressaisie.
///
/// Le mot de passe n'est JAMAIS envoyé au cloud. La clé de chiffrement des
/// sauvegardes est dérivée du mot de passe au moment du chiffrement
/// (PBKDF2 + sel par fichier, cf. `BackupCodec`) ; l'authentification
/// AES-256-GCM sert de vérification croisée lors d'une restauration sur un
/// nouvel appareil (un mauvais mot de passe = tag GCM invalide).
class MasterKeyService extends ChangeNotifier {
  static const String _kSalt = 'master_pw_salt_b64';
  static const String _kVerifier = 'master_pw_verifier_b64';
  static const String _kKdf = 'master_pw_kdf';
  static const String _ksPassword = 'cloud_sync_master_password';

  static const FlutterSecureStorage _secure = FlutterSecureStorage();

  /// Argon2id(password, salt) → 32 octets. Pur et déterministe ; exécuté en
  /// isolate. Exposé pour les tests.
  static Future<Uint8List> computeVerifier(String password, Uint8List salt) {
    return compute(_argon2idJob, (password, salt));
  }

  /// `true` si un mot de passe maître a déjà été défini.
  bool get isConfigured => LocalDatabase.settingsBox.get(_kVerifier) != null;

  /// Définit (ou remplace) le mot de passe maître.
  Future<void> setupPassword(String password) async {
    final salt = _randomBytes(16);
    final verifier = await computeVerifier(password, salt);
    await LocalDatabase.settingsBox.put(_kSalt, base64Encode(salt));
    await LocalDatabase.settingsBox.put(_kVerifier, base64Encode(verifier));
    await LocalDatabase.settingsBox.put(_kKdf, 'argon2id-v1');
    await _secure.write(key: _ksPassword, value: password);
    notifyListeners();
  }

  /// Vérifie un mot de passe contre le vérificateur local (temps constant).
  Future<bool> verifyPassword(String password) async {
    final saltB64 = LocalDatabase.settingsBox.get(_kSalt);
    final verB64 = LocalDatabase.settingsBox.get(_kVerifier);
    if (saltB64 == null || verB64 == null) return false;
    final actual = await computeVerifier(password, base64Decode(saltB64));
    return _constantTimeEquals(actual, base64Decode(verB64));
  }

  /// Mot de passe mémorisé dans le trousseau (pour chiffrer sans ressaisie).
  /// `null` si non configuré.
  Future<String?> storedPassword() => _secure.read(key: _ksPassword);

  /// Efface le mot de passe maître (déconnexion / reset).
  Future<void> clear() async {
    await LocalDatabase.settingsBox.delete(_kSalt);
    await LocalDatabase.settingsBox.delete(_kVerifier);
    await LocalDatabase.settingsBox.delete(_kKdf);
    await _secure.delete(key: _ksPassword);
    notifyListeners();
  }

  static Uint8List _randomBytes(int n) {
    final r = Random.secure();
    return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
