import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Instance partagée de [FlutterSecureStorage] avec des options qui
/// **persistent correctement sur toutes les plateformes**.
///
/// En particulier sur **macOS** : le trousseau « data protection » utilisé par
/// défaut par flutter_secure_storage ne conserve pas toujours les valeurs pour
/// une app non publiée sur le Mac App Store, ce qui se traduit par une
/// « Passphrase manquante » alors que l'app se croit configurée. On force donc
/// le trousseau classique (`useDataProtectionKeyChain: false`), exactement
/// comme [SecureKeyStore] (clé de chiffrement Hive) qui, lui, fonctionne.
///
/// À utiliser PARTOUT au lieu de `FlutterSecureStorage()`.
const FlutterSecureStorage appSecureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  ),
  mOptions: MacOsOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
    useDataProtectionKeyChain: false,
  ),
);
