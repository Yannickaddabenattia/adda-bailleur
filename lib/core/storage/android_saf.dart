import 'package:flutter/services.dart';

/// Un fichier listé dans un dossier SAF.
class SafFile {
  final String name;
  final DateTime modified;
  final int size;
  const SafFile(
      {required this.name, required this.modified, required this.size});
}

/// Dossier choisi via le sélecteur Android (Storage Access Framework).
class SafFolder {
  /// URI d'arborescence persistante (`content://…/tree/…`).
  final String uri;
  final String name;
  const SafFolder({required this.uri, required this.name});
}

/// Accès **Storage Access Framework** (Android) : choix d'un dossier à
/// permission persistante puis écriture / lecture / liste / suppression de
/// fichiers — la seule voie conforme Google Play pour écrire dans un dossier
/// utilisateur (ex. dossier synchronisé pCloud/Drive). Canal natif
/// `adda_location/saf`.
class AndroidSaf {
  static const MethodChannel _ch = MethodChannel('adda_location/saf');

  /// Ouvre le sélecteur de dossier système et renvoie le dossier choisi
  /// (avec permission persistante). `null` si annulé.
  static Future<SafFolder?> pickDirectory() async {
    final r = await _ch.invokeMapMethod<String, dynamic>('pickDirectory');
    if (r == null) return null;
    final uri = r['uri'] as String?;
    if (uri == null || uri.isEmpty) return null;
    return SafFolder(uri: uri, name: (r['name'] as String?) ?? '');
  }

  /// `true` si l'URI est toujours accessible en écriture (permission valide).
  static Future<bool> isAccessible(String uri) async =>
      (await _ch.invokeMethod<bool>('isAccessible', {'uri': uri})) ?? false;

  /// Écrit (remplace) un fichier dans le dossier ; renvoie l'URI du fichier.
  static Future<String> writeFile(
      String uri, String name, Uint8List bytes) async {
    final r = await _ch.invokeMethod<String>(
        'writeFile', {'uri': uri, 'name': name, 'bytes': bytes});
    return r ?? '';
  }

  static Future<List<SafFile>> listFiles(String uri) async {
    final r = await _ch.invokeListMethod<dynamic>('listFiles', {'uri': uri});
    if (r == null) return [];
    return r
        .map((e) {
          final m = (e as Map).cast<String, dynamic>();
          return SafFile(
            name: (m['name'] as String?) ?? '',
            modified: DateTime.fromMillisecondsSinceEpoch(
                (m['modified'] as num?)?.toInt() ?? 0),
            size: (m['size'] as num?)?.toInt() ?? 0,
          );
        })
        .where((f) => f.name.isNotEmpty)
        .toList();
  }

  static Future<Uint8List?> readFile(String uri, String name) async {
    return _ch.invokeMethod<Uint8List>('readFile', {'uri': uri, 'name': name});
  }

  static Future<void> deleteFile(String uri, String name) async {
    await _ch.invokeMethod('deleteFile', {'uri': uri, 'name': name});
  }
}
