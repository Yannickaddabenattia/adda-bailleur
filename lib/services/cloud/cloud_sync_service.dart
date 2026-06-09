import 'package:flutter/foundation.dart';

import '../../core/backup/backup_codec.dart';
import '../../core/storage/local_database.dart';
import '../auto_backup_service.dart' show BackupFileName;
import '../backup_service.dart';
import '../master_key_service.dart';
import 'dropbox_sync_provider.dart';
import 'folder_cloud_provider.dart';
import 'google_drive_sync_provider.dart';
import 'icloud_sync_provider.dart';
import 'pcloud_sync_provider.dart';

/// Services cloud proposés à l'utilisateur.
enum CloudProvider { folder, pcloud, dropbox, googleDrive, icloud }

extension CloudProviderMeta on CloudProvider {
  String get id => name;

  String get displayName {
    switch (this) {
      case CloudProvider.folder:
        return 'Dossier synchronisé';
      case CloudProvider.pcloud:
        return 'pCloud';
      case CloudProvider.dropbox:
        return 'Dropbox';
      case CloudProvider.googleDrive:
        return 'Google Drive';
      case CloudProvider.icloud:
        return 'iCloud Drive';
    }
  }

  /// `true` si l'implémentation est opérationnelle aujourd'hui. Les services
  /// OAuth directs nécessitent des identifiants développeur (à venir).
  bool get isAvailable => this == CloudProvider.folder;

  static CloudProvider fromId(String id) => CloudProvider.values.firstWhere(
        (p) => p.name == id,
        orElse: () => CloudProvider.folder,
      );
}

/// Une sauvegarde présente côté cloud.
class CloudBackupEntry {
  /// Identifiant/chemin distant (opaque, propre au provider).
  final String id;
  final String name;
  final DateTime modified;
  final int size;

  const CloudBackupEntry({
    required this.id,
    required this.name,
    required this.modified,
    required this.size,
  });
}

/// Erreur de transport cloud (réseau, quota, auth…), avec indication de
/// possibilité de réessai.
class CloudSyncException implements Exception {
  final String message;
  final bool retryable;
  const CloudSyncException(this.message, {this.retryable = false});
  @override
  String toString() => 'CloudSyncException: $message';
}

/// Résultat d'une opération de synchronisation.
class CloudSyncResult {
  final bool ok;
  final String? message;
  const CloudSyncResult.success([this.message]) : ok = true;
  const CloudSyncResult.failure(this.message) : ok = false;
}

/// Transport cloud abstrait : chaque service (dossier synchronisé, pCloud,
/// Dropbox, Drive, iCloud) en fournit une implémentation. Le provider ne
/// connaît QUE des octets déjà chiffrés — il ne déchiffre jamais rien.
abstract class CloudSyncProvider {
  CloudProvider get kind;

  /// `true` si déjà authentifié/configuré (aucun re-login nécessaire).
  Future<bool> isAuthenticated();

  /// Lance l'authentification (OAuth, ou sélection de dossier). Renvoie
  /// `true` si l'utilisateur a bien connecté/sélectionné.
  Future<bool> authenticate();

  /// Téléverse une sauvegarde chiffrée. Renvoie l'identifiant distant.
  Future<String> uploadBackup({
    required String fileName,
    required Uint8List bytes,
  });

  /// Liste les sauvegardes disponibles, triées de la plus récente à la plus
  /// ancienne.
  Future<List<CloudBackupEntry>> listBackups();

  /// Télécharge le contenu (chiffré) d'une sauvegarde.
  Future<Uint8List> downloadBackup(CloudBackupEntry entry);

  /// Oublie les identifiants / la configuration.
  Future<void> logout();
}

/// Orchestrateur de la synchronisation cloud : relie le **mot de passe
/// maître** (chiffrement), le **BackupService** (sérialisation/fusion) et le
/// **provider** choisi (transport). Aucune donnée en clair ne quitte
/// l'appareil ; aucun serveur ADDA n'est impliqué.
class CloudSyncService extends ChangeNotifier {
  static const String _kProvider = 'cloud_sync_provider';

  final MasterKeyService masterKey;
  CloudSyncProvider? _provider;

  CloudSyncService(this.masterKey) {
    final id = LocalDatabase.settingsBox.get(_kProvider);
    if (id != null) {
      _provider = _instantiate(CloudProviderMeta.fromId(id));
    }
  }

  CloudProvider? get activeProvider => _provider?.kind;
  bool get hasProvider => _provider != null;

  CloudSyncProvider _instantiate(CloudProvider kind) {
    switch (kind) {
      case CloudProvider.folder:
        return FolderCloudProvider();
      case CloudProvider.pcloud:
        return PCloudSyncProvider();
      case CloudProvider.dropbox:
        return DropboxSyncProvider();
      case CloudProvider.googleDrive:
        return GoogleDriveSyncProvider();
      case CloudProvider.icloud:
        return ICloudSyncProvider();
    }
  }

  /// Choisit un service et lance son authentification. Persiste le choix si
  /// l'authentification réussit.
  Future<CloudSyncResult> selectProvider(CloudProvider kind) async {
    final provider = _instantiate(kind);
    try {
      final ok = await provider.authenticate();
      if (!ok) return const CloudSyncResult.failure('Connexion annulée');
      _provider = provider;
      await LocalDatabase.settingsBox.put(_kProvider, kind.id);
      notifyListeners();
      return const CloudSyncResult.success();
    } on CloudSyncException catch (e) {
      return CloudSyncResult.failure(e.message);
    } catch (e) {
      return CloudSyncResult.failure(e.toString());
    }
  }

  /// Sauvegarde chiffrée vers le cloud. Réessaie [maxRetries] fois en cas
  /// d'erreur réseau transitoire.
  Future<CloudSyncResult> backupNow({int maxRetries = 2}) async {
    final provider = _provider;
    if (provider == null) {
      return const CloudSyncResult.failure('Aucun service cloud sélectionné');
    }
    if (!masterKey.isConfigured) {
      return const CloudSyncResult.failure('Mot de passe maître non défini');
    }
    final password = await masterKey.storedPassword();
    if (password == null || password.isEmpty) {
      return const CloudSyncResult.failure('Mot de passe indisponible');
    }

    final svc = BackupService();
    final file = await svc.exportEncrypted(passphrase: password);
    final bytes = await file.readAsBytes();
    try {
      await file.delete();
    } catch (_) {/* pas critique */}

    final fileName = BackupFileName.build(
      deviceTag: _deviceTag(),
      now: DateTime.now(),
    );

    CloudSyncException? lastErr;
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final id = await provider.uploadBackup(fileName: fileName, bytes: bytes);
        return CloudSyncResult.success(id);
      } on CloudSyncException catch (e) {
        lastErr = e;
        if (!e.retryable) break;
      } catch (e) {
        return CloudSyncResult.failure(e.toString());
      }
    }
    return CloudSyncResult.failure(
        lastErr?.message ?? 'Échec du téléversement');
  }

  /// Restaure la dernière sauvegarde du cloud avec [password] (fusion dans
  /// Hive). En cas de succès, mémorise le mot de passe maître localement.
  Future<CloudSyncResult> restoreLatest(String password) async {
    final provider = _provider;
    if (provider == null) {
      return const CloudSyncResult.failure('Aucun service cloud sélectionné');
    }
    try {
      final entries = await provider.listBackups();
      if (entries.isEmpty) {
        return const CloudSyncResult.failure('Aucune sauvegarde trouvée');
      }
      final bytes = await provider.downloadBackup(entries.first);
      await BackupService().importEncrypted(bytes: bytes, passphrase: password);
      await masterKey.setupPassword(password);
      notifyListeners();
      return CloudSyncResult.success(entries.first.name);
    } on BackupDecryptionException {
      return const CloudSyncResult.failure('Mot de passe incorrect');
    } on CloudSyncException catch (e) {
      return CloudSyncResult.failure(e.message);
    } catch (e) {
      return CloudSyncResult.failure(e.toString());
    }
  }

  /// Déconnecte le service cloud (sans toucher aux données locales).
  Future<void> disconnect() async {
    await _provider?.logout();
    _provider = null;
    await LocalDatabase.settingsBox.delete(_kProvider);
    notifyListeners();
  }

  String _deviceTag() {
    final id = LocalDatabase.settingsBox.get('auto_backup_device_id') ?? '';
    final hex = id.replaceAll('-', '');
    return hex.isEmpty ? '00000000' : hex.padRight(8, '0').substring(0, 8);
  }
}
