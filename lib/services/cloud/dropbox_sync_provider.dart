import 'dart:typed_data';

import 'cloud_sync_service.dart';

/// Transport Dropbox via l'API HTTP v2 + OAuth 2 (PKCE).
///
/// Implémentation à compléter quand les identifiants seront fournis :
///  1. Enregistrer une app sur https://www.dropbox.com/developers/apps
///     (type « Scoped access », permission `files.content.write/read`).
///  2. Renseigner `App key` ci-dessous + le schéma de redirection
///     (`db-<appkey>://`) dans Info.plist / AndroidManifest.
///  3. OAuth PKCE via `flutter_appauth` ou flux manuel → access token.
///  4. uploadBackup  → POST https://content.dropboxapi.com/2/files/upload
///     listBackups   → POST https://api.dropboxapi.com/2/files/list_folder
///     downloadBackup→ POST https://content.dropboxapi.com/2/files/download
///
/// Le token est stocké dans le trousseau ; aucune donnée n'est déchiffrée ici.
class DropboxSyncProvider implements CloudSyncProvider {
  // static const String _appKey = '<À_RENSEIGNER>';

  @override
  CloudProvider get kind => CloudProvider.dropbox;

  static const CloudSyncException _notConfigured = CloudSyncException(
    'L\'intégration Dropbox nécessite des identifiants OAuth (à configurer). '
    'En attendant, utilisez « Dossier synchronisé » avec l\'app Dropbox.',
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
