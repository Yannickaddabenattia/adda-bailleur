import 'dart:io';

import 'package:flutter/foundation.dart';

/// Auto-enregistrement Linux : crée silencieusement au premier lancement
/// de l'application le fichier `.desktop` et les types MIME pour que le
/// double-clic sur un `.adlb` / `.adlr` / `.adli` ouvre directement
/// ADDA Bailleur depuis le gestionnaire de fichiers.
///
/// Idempotent : ne réécrit que si le contenu a changé (chemin du binaire
/// modifié après rebuild p.ex.).
class LinuxBootstrap {
  static const String _mimeBackup = 'application/x-adda-backup';
  static const String _mimeSignedEdl = 'application/x-adda-signed-edl';
  static const String _mimeIntervention = 'application/x-adda-intervention';
  static const String _desktopName = 'adda-bailleur.desktop';
  static const String _mimeFileName = 'adda-bailleur.xml';
  static const String _iconName = 'adda-bailleur';

  static Future<void> ensureRegistered() async {
    if (!Platform.isLinux) return;
    try {
      await _doRegister();
    } catch (e, s) {
      debugPrint('LinuxBootstrap échec : $e\n$s');
    }
  }

  static Future<void> _doRegister() async {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) return;

    final exePath = Platform.resolvedExecutable;
    if (exePath.isEmpty || !File(exePath).existsSync()) return;

    final desktopDir = Directory('$home/.local/share/applications');
    final mimeDir = Directory('$home/.local/share/mime/packages');
    final iconDir =
        Directory('$home/.local/share/icons/hicolor/512x512/apps');
    desktopDir.createSync(recursive: true);
    mimeDir.createSync(recursive: true);
    iconDir.createSync(recursive: true);

    final desktopFile = File('${desktopDir.path}/$_desktopName');
    final mimeFile = File('${mimeDir.path}/$_mimeFileName');
    final iconFile = File('${iconDir.path}/$_iconName.png');

    final desktopContent = '''
[Desktop Entry]
Type=Application
Name=ADDA Bailleur
GenericName=Gestion bailleur
Comment=Gestion locative complète : logements, locataires, quittances, EDL
Exec="$exePath" %f
Icon=$_iconName
Terminal=false
Categories=Office;Finance;
MimeType=$_mimeBackup;$_mimeSignedEdl;$_mimeIntervention;
StartupNotify=true
''';
    final mimeContent = '''
<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
  <mime-type type="$_mimeBackup">
    <comment>Sauvegarde ADDA Bailleur</comment>
    <comment xml:lang="fr">Sauvegarde ADDA Bailleur</comment>
    <icon name="$_iconName"/>
    <glob pattern="*.adlb"/>
  </mime-type>
  <mime-type type="$_mimeSignedEdl">
    <comment>État des lieux signé (locataire)</comment>
    <comment xml:lang="fr">État des lieux signé (locataire)</comment>
    <icon name="$_iconName"/>
    <glob pattern="*.adlr"/>
  </mime-type>
  <mime-type type="$_mimeIntervention">
    <comment>Demande d'intervention locataire</comment>
    <comment xml:lang="fr">Demande d'intervention locataire</comment>
    <icon name="$_iconName"/>
    <glob pattern="*.adli"/>
  </mime-type>
</mime-info>
''';

    var changed = false;
    if (!desktopFile.existsSync() ||
        desktopFile.readAsStringSync() != desktopContent) {
      desktopFile.writeAsStringSync(desktopContent);
      changed = true;
    }
    if (!mimeFile.existsSync() ||
        mimeFile.readAsStringSync() != mimeContent) {
      mimeFile.writeAsStringSync(mimeContent);
      changed = true;
    }

    if (!iconFile.existsSync()) {
      final iconSrc = _findIconAsset(exePath);
      if (iconSrc != null) {
        try {
          await iconSrc.copy(iconFile.path);
          changed = true;
        } catch (_) {}
      }
    }

    if (changed) {
      await _runQuiet('update-mime-database', [
        '$home/.local/share/mime',
      ]);
      await _runQuiet('update-desktop-database', [desktopDir.path]);
      await _runQuiet('gtk-update-icon-cache', [
        '--quiet',
        '$home/.local/share/icons/hicolor',
      ]);
      for (final mime in [_mimeBackup, _mimeSignedEdl, _mimeIntervention]) {
        await _runQuiet('xdg-mime', ['default', _desktopName, mime]);
      }
    }
  }

  static File? _findIconAsset(String exePath) {
    final exeDir = File(exePath).parent;
    final candidates = [
      File('${exeDir.path}/data/flutter_assets/assets/images/logo_square.png'),
      File('${exeDir.path}/data/flutter_assets/assets/images/logo.png'),
    ];
    for (final f in candidates) {
      if (f.existsSync()) return f;
    }
    return null;
  }

  static Future<void> _runQuiet(String exe, List<String> args) async {
    try {
      await Process.run(exe, args, runInShell: false);
    } catch (_) {/* commande non disponible */}
  }
}
