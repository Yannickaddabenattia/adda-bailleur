import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Gestion locale des photos (stockées en-dehors de Hive pour la taille).
///
/// Les photos sont rangées dans :
/// `<documents>/photos/<etatId>/<uuid>.jpg`
class PhotoStorage {
  static Future<Directory> _baseDir(String etatId) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/photos/$etatId');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  /// Copie le fichier source dans le stockage local et retourne le chemin final.
  static Future<String> saveImage({
    required String etatId,
    required String sourcePath,
  }) async {
    final base = await _baseDir(etatId);
    final extension = sourcePath.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
    final destPath = '${base.path}/${const Uuid().v4()}.$extension';
    await File(sourcePath).copy(destPath);
    return destPath;
  }

  static Future<void> deleteImage(String path) async {
    final f = File(path);
    if (f.existsSync()) {
      await f.delete();
    }
  }

  static Future<void> deleteAllForEtat(String etatId) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/photos/$etatId');
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
  }
}
