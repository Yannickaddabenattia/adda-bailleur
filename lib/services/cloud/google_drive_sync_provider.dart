import 'dart:typed_data';

import 'cloud_sync_service.dart';

/// Transport Google Drive via l'API Drive v3 + OAuth 2 (Google Sign-In).
///
/// Implémentation à compléter quand les identifiants seront fournis :
///  1. Console Google Cloud → activer « Google Drive API », créer des
///     identifiants OAuth (iOS + Android + macOS), écran de consentement.
///  2. Paquets `google_sign_in` + `googleapis` (scope
///     `https://www.googleapis.com/auth/drive.appdata` — dossier caché de
///     l'app, idéal pour des sauvegardes privées).
///  3. uploadBackup  → files.create (multipart) dans `appDataFolder`.
///     listBackups   → files.list (spaces=appDataFolder, orderBy=modifiedTime).
///     downloadBackup→ files.get (alt=media).
///
/// Le token OAuth est géré par google_sign_in ; rien n'est déchiffré ici.
class GoogleDriveSyncProvider implements CloudSyncProvider {
  @override
  CloudProvider get kind => CloudProvider.googleDrive;

  static const CloudSyncException _notConfigured = CloudSyncException(
    'L\'intégration Google Drive nécessite des identifiants OAuth (à '
    'configurer). En attendant, utilisez « Dossier synchronisé ».',
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
