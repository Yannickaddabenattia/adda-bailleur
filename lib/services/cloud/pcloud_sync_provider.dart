import 'dart:typed_data';

import 'cloud_sync_service.dart';

/// Transport pCloud via son API HTTP + OAuth 2.
///
/// Implémentation à compléter quand les identifiants seront fournis :
///  1. Créer une app sur https://docs.pcloud.com/ (My Applications) →
///     `client_id` + `client_secret`, définir l'URI de redirection.
///  2. OAuth 2 : https://my.pcloud.com/oauth2/authorize → code → token via
///     https://api.pcloud.com/oauth2_token. ATTENTION : choisir le bon hôte
///     d'API (`api.pcloud.com` zone US vs `eapi.pcloud.com` zone EU) selon le
///     `locationid` renvoyé.
///  3. uploadBackup  → /uploadfile (multipart, folderid du dossier app).
///     listBackups   → /listfolder.
///     downloadBackup→ /getfilelink puis GET du lien.
///
/// Le token est stocké dans le trousseau ; aucune donnée n'est déchiffrée ici.
class PCloudSyncProvider implements CloudSyncProvider {
  @override
  CloudProvider get kind => CloudProvider.pcloud;

  static const CloudSyncException _notConfigured = CloudSyncException(
    'L\'intégration directe pCloud nécessite des identifiants OAuth (à '
    'configurer). En attendant, utilisez « Dossier synchronisé » en pointant '
    'un dossier synchronisé par pCloud Drive.',
  );

  @override
  Future<bool> isAuthenticated() async => false;

  @override
  Future<bool> authenticate() async => throw _notConfigured;

  @override
  Future<String> uploadBackup({
    required String fileName,
    required Uint8List bytes,
  }) async =>
      throw _notConfigured;

  @override
  Future<List<CloudBackupEntry>> listBackups() async => throw _notConfigured;

  @override
  Future<Uint8List> downloadBackup(CloudBackupEntry entry) async =>
      throw _notConfigured;

  @override
  Future<void> logout() async {}
}
