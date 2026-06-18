import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:adda_location/core/storage/local_database.dart';
import 'package:adda_location/screens/account/delete_account_action.dart';
import 'package:adda_location/screens/onboarding/user_info_screen.dart';
import 'package:adda_location/services/auto_backup_service.dart';
import 'package:adda_location/services/master_key_service.dart';
import 'package:adda_location/services/user_service.dart';

/// UI test du flux de suppression de compte (Apple Guideline 5.1.1(v)).
///
/// On teste `confirmDeleteAccount` — la **source unique** appelée par les deux
/// points d'entrée (Réglages › COMPTE et écran Sauvegarde) — bout en bout :
/// tap → dialogue de confirmation → annulation OU suppression → chargement →
/// retour à l'onboarding, plus le chemin d'erreur.
///
/// `UserService` est remplacé par un faux (on vérifie que `deleteAccount` est
/// invoqué sans déclencher un vrai wipe), tandis que `MasterKeyService` et
/// `AutoBackupService` sont réels — d'où l'initialisation de Hive + le mock du
/// secure storage en `setUpAll` (le constructeur d'AutoBackupService lit
/// `settingsBox`).

/// Mock path_provider : toute requête de dossier renvoie [dir].
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

/// Faux UserService : enregistre l'appel et simule succès / latence / échec,
/// sans toucher au stockage réel.
class _FakeUserService extends UserService {
  int deleteCalls = 0;
  Object? errorToThrow;
  Future<void>? gate; // si non null, deleteAccount attend ce future

  @override
  Future<void> deleteAccount({
    MasterKeyService? masterKey,
    AutoBackupService? autoBackup,
  }) async {
    deleteCalls++;
    if (gate != null) await gate;
    if (errorToThrow != null) throw errorToThrow!;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  final secureStore = <String, String>{};

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('adda_del_ui_');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);

    // Mock du canal flutter_secure_storage (utilisé par les services réels).
    const secCh =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secCh, (call) async {
      final a = (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
      final key = a['key'] as String?;
      switch (call.method) {
        case 'read':
          return key == null ? null : secureStore[key];
        case 'write':
          if (key != null) secureStore[key] = a['value'] as String;
          return null;
        case 'delete':
          secureStore.remove(key);
          return null;
        case 'deleteAll':
          secureStore.clear();
          return null;
        case 'readAll':
          return Map<String, String>.from(secureStore);
        case 'containsKey':
          return secureStore.containsKey(key);
      }
      return null;
    });

    await LocalDatabase.init();
  });

  tearDownAll(() async {
    try {
      await LocalDatabase.wipeEverything();
    } catch (_) {}
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  /// Monte un écran minimal avec un bouton qui déclenche le flux, sous les
  /// providers requis par `confirmDeleteAccount`.
  Future<void> pumpHost(WidgetTester tester, _FakeUserService user) {
    return tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<UserService>.value(value: user),
          ChangeNotifierProvider<MasterKeyService>(
              create: (_) => MasterKeyService()),
          ChangeNotifierProvider<AutoBackupService>(
              create: (_) => AutoBackupService()),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => confirmDeleteAccount(ctx),
                  child: const Text('Lancer'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('affiche un dialogue de confirmation irréversible', (t) async {
    await pumpHost(t, _FakeUserService());

    await t.tap(find.text('Lancer'));
    await t.pumpAndSettle();

    expect(find.text('Supprimer mon compte ?'), findsOneWidget);
    expect(find.textContaining('définitive et irréversible'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Annuler'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Supprimer définitivement'),
        findsOneWidget);
  });

  testWidgets('Annuler ferme le dialogue sans rien supprimer', (t) async {
    final user = _FakeUserService();
    await pumpHost(t, user);

    await t.tap(find.text('Lancer'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(TextButton, 'Annuler'));
    await t.pumpAndSettle();

    expect(find.text('Supprimer mon compte ?'), findsNothing);
    expect(user.deleteCalls, 0);
    expect(find.byType(UserInfoScreen), findsNothing);
  });

  testWidgets(
      'Confirmer → chargement → deleteAccount → retour à l\'onboarding',
      (t) async {
    final user = _FakeUserService();
    final gate = Completer<void>();
    user.gate = gate.future; // bloque pour observer l'état de chargement
    await pumpHost(t, user);

    await t.tap(find.text('Lancer'));
    await t.pumpAndSettle();

    await t.tap(find.widgetWithText(TextButton, 'Supprimer définitivement'));
    // Pas de pumpAndSettle : l'indicateur de chargement tourne indéfiniment.
    await t.pump(); // ferme le dialogue de confirmation
    await t.pump(const Duration(milliseconds: 400)); // affiche le chargement

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(user.deleteCalls, 1);
    expect(find.byType(UserInfoScreen), findsNothing); // pas encore navigué

    gate.complete(); // la suppression aboutit
    await t.pump(); // résout le future (pop du chargement + pushAndRemoveUntil)
    // Assez de temps pour la fermeture du chargement ET la transition d'entrée
    // de l'onboarding, après quoi la route d'origine est retirée de la pile.
    await t.pump(const Duration(seconds: 1));

    expect(find.byType(UserInfoScreen), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Lancer'), findsNothing); // l'écran d'origine est retiré
  });

  testWidgets('échec de deleteAccount → SnackBar d\'erreur, pas de navigation',
      (t) async {
    final user = _FakeUserService()..errorToThrow = Exception('boom');
    await pumpHost(t, user);

    await t.tap(find.text('Lancer'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(TextButton, 'Supprimer définitivement'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400)); // chargement puis échec
    await t.pump(const Duration(milliseconds: 400)); // entrée du SnackBar

    expect(user.deleteCalls, 1);
    expect(find.textContaining('Échec de la suppression'), findsOneWidget);
    expect(find.byType(UserInfoScreen), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
