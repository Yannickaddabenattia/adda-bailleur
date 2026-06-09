import 'dart:io';
import 'dart:typed_data';

import '../../core/storage/local_database.dart';
import '../../core/storage/secure_folder.dart';
import '../auto_backup_service.dart' show BackupFileName;
import 'cloud_sync_service.dart';

/// Transport via un **dossier synchronisé** par le client OS d'un fournisseur
/// (pCloud Drive, Dropbox, Google Drive, iCloud Drive, OneDrive, NAS…).
///
/// C'est l'implémentation opérationnelle aujourd'hui : aucun OAuth, l'accès
/// au dossier choisi est conservé via un security-scoped bookmark. Le cloud
/// se charge de propager les fichiers `.adls` (déjà chiffrés) entre appareils.
class FolderCloudProvider implements CloudSyncProvider {
  static const String _kPath = 'cloud_folder_path';
  static const String _kBookmark = 'cloud_folder_bookmark';

  @override
  CloudProvider get kind => CloudProvider.folder;

  String? get _path {
    final p = LocalDatabase.settingsBox.get(_kPath);
    return (p == null || p.isEmpty) ? null : p;
  }

  String? get _bookmark {
    final b = LocalDatabase.settingsBox.get(_kBookmark);
    return (b == null || b.isEmpty) ? null : b;
  }

  @override
  Future<bool> isAuthenticated() async => _path != null;

  @override
  Future<bool> authenticate() async {
    if (!SecureFolder.isSupported) {
      throw const CloudSyncException(
          'La sélection de dossier n\'est pas supportée sur cette plateforme');
    }
    final picked = await SecureFolder.pickDirectory();
    if (picked == null) return false;
    await LocalDatabase.settingsBox.put(_kPath, picked.path);
    await LocalDatabase.settingsBox.put(_kBookmark, picked.bookmark);
    return true;
  }

  /// Exécute [body] en ayant (ré)ouvert l'accès security-scoped au dossier.
  Future<T> _withAccess<T>(Future<T> Function(String folder) body) async {
    final stored = _path;
    if (stored == null) {
      throw const CloudSyncException('Dossier de sauvegarde non configuré');
    }
    final bm = _bookmark;
    String? resolved;
    try {
      if (bm != null) resolved = await SecureFolder.startAccess(bm);
      final folder = resolved ?? stored;
      if (!Directory(folder).existsSync()) {
        throw const CloudSyncException('Dossier inaccessible', retryable: true);
      }
      return await body(folder);
    } finally {
      if (bm != null && resolved != null) {
        await SecureFolder.stopAccess(bm);
      }
    }
  }

  @override
  Future<String> uploadBackup({
    required String fileName,
    required Uint8List bytes,
  }) {
    return _withAccess((folder) async {
      final target = '$folder${Platform.pathSeparator}$fileName';
      final tmp = File('$target.tmp');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(target); // remplacement atomique
      return target;
    });
  }

  @override
  Future<List<CloudBackupEntry>> listBackups() {
    return _withAccess((folder) async {
      final entries = <CloudBackupEntry>[];
      for (final f in Directory(folder).listSync().whereType<File>()) {
        final name = f.uri.pathSegments.last;
        final info = BackupFileName.tryParse(name);
        if (info == null) continue;
        entries.add(CloudBackupEntry(
          id: f.path,
          name: name,
          modified: info.dateTime,
          size: f.statSync().size,
        ));
      }
      entries.sort((a, b) => b.modified.compareTo(a.modified));
      return entries;
    });
  }

  @override
  Future<Uint8List> downloadBackup(CloudBackupEntry entry) {
    return _withAccess((_) async {
      final f = File(entry.id);
      if (!f.existsSync()) {
        throw const CloudSyncException('Fichier de sauvegarde introuvable');
      }
      return f.readAsBytes();
    });
  }

  @override
  Future<void> logout() async {
    await LocalDatabase.settingsBox.delete(_kPath);
    await LocalDatabase.settingsBox.delete(_kBookmark);
  }
}
