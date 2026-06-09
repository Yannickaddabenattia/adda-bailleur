import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:adda_location/core/storage/local_database.dart';
import 'package:adda_location/services/auto_backup_service.dart';

/// Mock path_provider : toutes les requêtes de dossier renvoient [dir].
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.dir);
  final String dir;
  @override
  Future<String?> getTemporaryPath() async => dir;
  @override
  Future<String?> getApplicationSupportPath() async => dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
  @override
  Future<String?> getApplicationCachePath() async => dir;
  @override
  Future<String?> getLibraryPath() async => dir;
  @override
  Future<String?> getDownloadsPath() async => dir;
  @override
  Future<String?> getExternalStoragePath() async => dir;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cycle complet : écriture .adls + détection autre appareil + import',
      () async {
    final hiveDir = await Directory.systemTemp.createTemp('adda_hive_');
    final backupFolder = await Directory.systemTemp.createTemp('adda_backup_');
    final secure = <String, String>{};

    PathProviderPlatform.instance = _FakePathProvider(hiveDir.path);

    const secCh =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(secCh, (call) async {
      final a = (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
      final key = a['key'] as String?;
      switch (call.method) {
        case 'read':
          return key == null ? null : secure[key];
        case 'write':
          if (key != null) secure[key] = a['value'] as String;
          return null;
        case 'delete':
          secure.remove(key);
          return null;
        case 'deleteAll':
          secure.clear();
          return null;
        case 'containsKey':
          return secure.containsKey(key);
        case 'readAll':
          return Map<String, String>.from(secure);
      }
      return null;
    });

    await LocalDatabase.init();
    final svc = AutoBackupService();

    addTearDown(() async {
      svc.dispose();
      messenger.setMockMethodCallHandler(secCh, null);
      try {
        await hiveDir.delete(recursive: true);
      } catch (_) {}
      try {
        await backupFolder.delete(recursive: true);
      } catch (_) {}
    });

    // 1) Configuration (sans bookmark → écriture directe dans le dossier).
    await svc.configure(
      folderPath: backupFolder.path,
      passphrase: 'passe-de-test-123',
      bookmark: null,
    );
    expect(svc.isEnabled, isTrue);

    // 2) Première sauvegarde manuelle → un .adls préfixé du tag device.
    final r1 = await svc.runIfNeeded(trigger: AutoBackupTrigger.manual);
    expect(r1.didBackup, isTrue, reason: 'le premier backup doit s\'écrire');
    final adls = backupFolder
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((n) => n.endsWith('.adls'))
        .toList();
    expect(adls.length, 1);
    final parsed = BackupFileName.tryParse(adls.first);
    expect(parsed, isNotNull);
    expect(parsed!.deviceTag, isNotNull,
        reason: 'le nom doit porter le tag device');
    expect(parsed.deviceTag!.length, 8);

    // 3) Sauvegarde sans changement → dédup par hash (rien réécrit).
    final r2 = await svc.runIfNeeded(trigger: AutoBackupTrigger.manual);
    expect(r2.didBackup, isFalse);
    expect(r2.reason, contains('Aucun changement'));

    // 4) Simule un fichier d'un AUTRE appareil : copie de notre backup valide,
    //    renommé avec un tag étranger et une date future.
    final ourPath =
        '${backupFolder.path}${Platform.pathSeparator}${adls.first}';
    const foreignName = 'addalocation_ffffffff_2099-01-01_120000.adls';
    await File(ourPath)
        .copy('${backupFolder.path}${Platform.pathSeparator}$foreignName');

    // 5) Détection du backup étranger.
    await svc.checkForForeignBackups();
    expect(svc.pendingForeign, isNotNull,
        reason: 'le fichier d\'un autre appareil doit être détecté');
    expect(svc.pendingForeign!.deviceTag, 'ffffffff');

    // 6) Import (fusion) en 1 tap.
    final imp = await svc.importForeignBackup();
    expect(imp.didBackup, isTrue, reason: 'la fusion doit réussir');
    expect(svc.pendingForeign, isNull);

    // 7) Re-détection → plus rien (watermark : déjà importé).
    await svc.checkForForeignBackups();
    expect(svc.pendingForeign, isNull,
        reason: 'un fichier déjà importé ne doit pas être reproposé');
  });
}
