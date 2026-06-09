import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:adda_location/core/storage/local_database.dart';
import 'package:adda_location/services/master_key_service.dart';
import 'package:adda_location/services/cloud/cloud_sync_service.dart';

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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cycle cloud : mot de passe maître → chiffrement → upload → restore',
      () async {
    final hiveDir = await Directory.systemTemp.createTemp('adda_hive_');
    final cloudDir = await Directory.systemTemp.createTemp('adda_cloud_');
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

    addTearDown(() async {
      messenger.setMockMethodCallHandler(secCh, null);
      try {
        await hiveDir.delete(recursive: true);
      } catch (_) {}
      try {
        await cloudDir.delete(recursive: true);
      } catch (_) {}
    });

    // Provider « dossier » configuré directement (on contourne le picker natif).
    await LocalDatabase.settingsBox.put('cloud_sync_provider', 'folder');
    await LocalDatabase.settingsBox.put('cloud_folder_path', cloudDir.path);
    await LocalDatabase.settingsBox.put('cloud_folder_bookmark', '');

    const password = 'motDePasseMaitre!2026';
    final masterKey = MasterKeyService();
    await masterKey.setupPassword(password);
    expect(masterKey.isConfigured, isTrue);
    expect(await masterKey.verifyPassword(password), isTrue);
    expect(await masterKey.verifyPassword('mauvais'), isFalse);

    final cloud = CloudSyncService(masterKey);
    expect(cloud.activeProvider, CloudProvider.folder);

    // 1) Sauvegarde chiffrée vers le « cloud » (dossier).
    final up = await cloud.backupNow();
    expect(up.ok, isTrue, reason: up.message);
    final adls = cloudDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.adls'))
        .toList();
    expect(adls.length, 1, reason: 'une sauvegarde chiffrée doit être déposée');

    // 2) Restauration avec le bon mot de passe → fusion OK.
    final ok = await cloud.restoreLatest(password);
    expect(ok.ok, isTrue, reason: ok.message);

    // 3) Restauration avec un mauvais mot de passe → refus explicite.
    final bad = await cloud.restoreLatest('mauvais-mot-de-passe');
    expect(bad.ok, isFalse);
    expect(bad.message, contains('Mot de passe incorrect'));
  });
}
