import 'dart:typed_data';

import 'cloud_sync_service.dart';

/// Transport iCloud.
///
/// IMPORTANT : Apple n'expose **aucune API OAuth/REST** permettant à une app
/// tierce de déposer des fichiers dans l'iCloud Drive d'un utilisateur avec un
/// email + mot de passe. Les seules voies possibles sont :
///   - **CloudKit** (conteneur iCloud propre à l'app, lié à l'Apple ID
///     présent SUR l'appareil — pas d'email/mot de passe, iOS/macOS only) ;
///   - le **dossier iCloud Drive** via le sélecteur de fichiers → c'est ce que
///     fait déjà « Dossier synchronisé » (recommandé).
///
/// Ce provider reste donc volontairement non implémenté : pour iCloud,
/// sélectionner « Dossier synchronisé » et pointer un dossier dans iCloud
/// Drive. Une future variante CloudKit pourrait être ajoutée ici.
class ICloudSyncProvider implements CloudSyncProvider {
  @override
  CloudProvider get kind => CloudProvider.icloud;

  static const CloudSyncException _useFolder = CloudSyncException(
    'iCloud ne permet pas l\'accès tiers par email/mot de passe. Pour iCloud, '
    'choisissez « Dossier synchronisé » et pointez un dossier d\'iCloud Drive.',
  );

  @override
  Future<bool> isAuthenticated() async => false;

  @override
  Future<bool> authenticate() async => throw _useFolder;

  @override
  Future<String> uploadBackup({
    required String fileName,
    required Uint8List bytes,
  }) async =>
      throw _useFolder;

  @override
  Future<List<CloudBackupEntry>> listBackups() async => throw _useFolder;

  @override
  Future<Uint8List> downloadBackup(CloudBackupEntry entry) async =>
      throw _useFolder;

  @override
  Future<void> logout() async {}
}
