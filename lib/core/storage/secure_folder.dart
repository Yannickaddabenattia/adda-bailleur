import 'dart:io';

import 'package:flutter/services.dart';

/// Dossier choisi par l'utilisateur, sélectionné nativement avec un
/// *security-scoped bookmark* pour que l'accès persiste après redémarrage
/// de l'app (obligatoire en bac à sable iOS / macOS).
class PickedFolder {
  /// Chemin POSIX du dossier au moment de la sélection.
  final String path;

  /// Bookmark encodé en base64 (résolvable après relance). Vide si la
  /// plateforme ne le supporte pas (le chemin seul est alors utilisé).
  final String bookmark;

  const PickedFolder({required this.path, required this.bookmark});
}

/// Accès à un dossier externe (cloud monté, disque, NAS, image disque…) avec
/// persistance d'autorisation via security-scoped bookmarks.
///
/// Implémenté nativement (canal `adda_location/secure_folder`) sur iOS et
/// macOS. Sur les autres plateformes, [isSupported] est `false` et l'app
/// retombe sur la sélection classique par chemin.
class SecureFolder {
  static const MethodChannel _ch =
      MethodChannel('adda_location/secure_folder');

  /// `true` si la plateforme gère les bookmarks (iOS / macOS sandboxés).
  static bool get isSupported => Platform.isIOS || Platform.isMacOS;

  /// Ouvre le sélecteur de dossier natif et renvoie le dossier choisi avec
  /// son bookmark. `null` si l'utilisateur annule.
  static Future<PickedFolder?> pickDirectory() async {
    if (!isSupported) return null;
    final res = await _ch.invokeMapMethod<String, dynamic>('pickDirectory');
    if (res == null) return null;
    final path = res['path'] as String?;
    if (path == null || path.isEmpty) return null;
    return PickedFolder(
      path: path,
      bookmark: (res['bookmark'] as String?) ?? '',
    );
  }

  /// Résout [bookmark], commence l'accès security-scoped et renvoie le chemin
  /// résolu (à utiliser pour les écritures). Renvoie `null` si le bookmark est
  /// vide, périmé ou non résolvable — l'appelant retombe alors sur le chemin
  /// stocké. **Doit être suivi d'un [stopAccess] dans un `finally`.**
  static Future<String?> startAccess(String bookmark) async {
    if (!isSupported || bookmark.isEmpty) return null;
    try {
      final res =
          await _ch.invokeMapMethod<String, dynamic>('startAccess', {
        'bookmark': bookmark,
      });
      return res?['path'] as String?;
    } on PlatformException {
      return null;
    }
  }

  /// Relâche l'accès ouvert par [startAccess]. Sans effet si rien n'était
  /// ouvert pour ce bookmark.
  static Future<void> stopAccess(String bookmark) async {
    if (!isSupported || bookmark.isEmpty) return;
    try {
      await _ch.invokeMethod('stopAccess', {'bookmark': bookmark});
    } on PlatformException {
      // pas critique : l'accès sera relâché à la fin du process de toute façon
    }
  }
}
