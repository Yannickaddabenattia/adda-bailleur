import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Stockage local des contrats de bail (PDF) — un dossier par logement.
///
/// Les fichiers sont rangés dans :
/// `<documents>/contrats/<logementId>/<basename>.pdf`
class ContratStorage {
  static Future<Directory> _baseDir(String logementId) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/contrats/$logementId');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  /// Copie le PDF source dans le stockage local et retourne le chemin final.
  /// Préserve le nom d'origine ; ajoute un suffixe `(n)` en cas de collision.
  static Future<String> addContrat({
    required String logementId,
    required String sourcePath,
    required String originalName,
  }) async {
    final base = await _baseDir(logementId);
    final sanitized = _sanitize(originalName);
    final lower = sanitized.toLowerCase();
    final stem = lower.endsWith('.pdf')
        ? sanitized.substring(0, sanitized.length - 4)
        : sanitized;

    var candidate = '${base.path}/$stem.pdf';
    var n = 1;
    while (File(candidate).existsSync()) {
      candidate = '${base.path}/$stem ($n).pdf';
      n++;
    }
    await File(sourcePath).copy(candidate);
    return candidate;
  }

  static Future<void> deleteContrat(String path) async {
    final f = File(path);
    if (f.existsSync()) {
      await f.delete();
    }
  }

  static String _sanitize(String name) {
    final cleaned = name.replaceAll(RegExp(r'[\\/]'), '_').trim();
    return cleaned.isEmpty ? 'contrat.pdf' : cleaned;
  }
}
