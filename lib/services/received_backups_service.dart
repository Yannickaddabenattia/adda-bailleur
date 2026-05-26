import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Métadonnées d'un fichier de sauvegarde reçu et conservé dans le sandbox
/// de l'application.
class ReceivedBackup {
  final File file;
  final DateTime receivedAt;
  final int size;

  const ReceivedBackup({
    required this.file,
    required this.receivedAt,
    required this.size,
  });

  String get name => file.path.split(Platform.pathSeparator).last;
}

/// Conserve les fichiers `.adlb` (sauvegardes) et `.adlr` (retours de
/// signature) reçus depuis l'extérieur (AirDrop, Fichiers, partage Android…)
/// dans un dossier nommé "ADDA Bailleur document".
///
/// - iOS / macOS : sous `Documents/` de l'app, visible dans l'app Fichiers
///   grâce à `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace`.
/// - Android : sous le stockage externe app-scopé
///   (`/storage/emulated/0/Android/data/<pkg>/files/`), visible dans Fichiers.
///
/// L'ancien dossier `sauvegardes_recues/` (versions <= 1.0.0) est migré
/// automatiquement vers le nouveau nom à la première utilisation.
class ReceivedBackupsService extends ChangeNotifier {
  static const _folderName = 'ADDA Bailleur document';
  static const _legacyFolderName = 'sauvegardes_recues';

  /// Nombre maximum de fichiers conservés dans le dossier. Au-delà, les
  /// plus anciens (date de modification) sont supprimés en FIFO pour ne
  /// pas saturer l'espace de stockage.
  static const maxArchivedFiles = 10;

  bool _migrated = false;

  Future<Directory> _baseDir() async {
    if (Platform.isAndroid) {
      final ext = await getExternalStorageDirectory();
      if (ext != null) return ext;
    }
    return getApplicationDocumentsDirectory();
  }

  Future<Directory> _ensureDir() async {
    final base = await _baseDir();
    final dir = Directory('${base.path}/$_folderName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    await _migrateLegacyIfNeeded(base, dir);
    return dir;
  }

  Future<void> _migrateLegacyIfNeeded(Directory base, Directory target) async {
    if (_migrated) return;
    _migrated = true;
    // L'ancien dossier vivait toujours sous getApplicationDocumentsDirectory(),
    // y compris sur Android. On le vérifie là spécifiquement.
    final docs = await getApplicationDocumentsDirectory();
    final legacy = Directory('${docs.path}/$_legacyFolderName');
    if (!await legacy.exists()) return;
    try {
      await for (final entity in legacy.list()) {
        if (entity is! File) continue;
        final name = entity.path.split(Platform.pathSeparator).last;
        final dest = File('${target.path}/$name');
        if (await dest.exists()) continue; // ne pas écraser
        await entity.copy(dest.path);
        try {
          await entity.delete();
        } catch (_) {/* fichier verrouillé, on laisse */}
      }
      // Si vide, on retire le dossier legacy
      final remaining = await legacy.list().toList();
      if (remaining.isEmpty) {
        await legacy.delete();
      }
    } catch (e, s) {
      debugPrint('ReceivedBackupsService legacy migration error: $e\n$s');
    }
  }

  /// Copie [source] dans le dossier "ADDA Bailleur document" et renvoie le
  /// fichier persistant. Si un fichier portant exactement le même nom existe
  /// déjà, ajoute un suffixe horodaté.
  Future<File> save(File source) async {
    final dir = await _ensureDir();
    final original = source.path.split(Platform.pathSeparator).last;
    var dest = File('${dir.path}/$original');
    if (await dest.exists()) {
      final ts = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final dot = original.lastIndexOf('.');
      final base = dot < 0 ? original : original.substring(0, dot);
      final ext = dot < 0 ? '' : original.substring(dot);
      dest = File('${dir.path}/${base}_$ts$ext');
    }
    await source.copy(dest.path);
    await _enforceCap(dir, keep: dest.path);
    notifyListeners();
    return dest;
  }

  /// Supprime les fichiers les plus anciens (.adlb + .adlr) jusqu'à ce qu'il
  /// en reste au plus [maxArchivedFiles]. Le fichier [keep] vient d'être
  /// copié et n'est jamais supprimé même s'il est le plus ancien selon le
  /// FS (cas de copie qui préserve la mtime de la source).
  Future<void> _enforceCap(Directory dir, {required String keep}) async {
    final entries = await dir.list().toList();
    final files = entries.whereType<File>().where((f) {
      final l = f.path.toLowerCase();
      return l.endsWith('.adlb') || l.endsWith('.adlr');
    }).toList();
    if (files.length <= maxArchivedFiles) return;

    final stats = <({File file, DateTime modified})>[];
    for (final f in files) {
      final st = await f.stat();
      stats.add((file: f, modified: st.modified));
    }
    stats.sort((a, b) => a.modified.compareTo(b.modified)); // plus ancien d'abord

    var toDelete = stats.length - maxArchivedFiles;
    for (final s in stats) {
      if (toDelete <= 0) break;
      if (s.file.path == keep) continue;
      try {
        await s.file.delete();
        toDelete--;
      } catch (e, st) {
        debugPrint('ReceivedBackupsService cap delete error: $e\n$st');
      }
    }
  }

  /// Liste les sauvegardes `.adlb` conservées dans "ADDA Bailleur document/",
  /// de la plus récente à la plus ancienne (date de modification). Les
  /// fichiers `.adlr` (retours de signature) y sont aussi archivés mais ne
  /// figurent pas ici — l'écran "Sauvegardes reçues" n'est conçu que pour
  /// les backups. Les utilisateurs peuvent retrouver les `.adlr` via
  /// l'application Fichiers du système.
  Future<List<ReceivedBackup>> list() async {
    final dir = await _ensureDir();
    final entries = await dir.list().toList();
    final files = entries
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.adlb'))
        .toList();
    final results = <ReceivedBackup>[];
    for (final f in files) {
      final stat = await f.stat();
      results.add(ReceivedBackup(
        file: f,
        receivedAt: stat.modified,
        size: stat.size,
      ));
    }
    results.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    return results;
  }

  Future<void> delete(File f) async {
    if (await f.exists()) {
      await f.delete();
      notifyListeners();
    }
  }
}
