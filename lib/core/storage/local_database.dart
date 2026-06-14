import 'dart:io';

import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../../models/credit_immobilier.dart';
import '../../models/depense.dart';
import '../../models/element_piece.dart';
import '../../models/etat_des_lieux.dart';
import '../../models/fiscal_settings.dart';
import '../../models/locataire.dart';
import '../../models/logement.dart';
import '../../models/piece.dart';
import '../../models/plan_logement.dart';
import '../../models/quittance.dart';
import '../../models/avenant.dart';
import '../../models/bail_template.dart';
import '../../models/contrat_bail.dart';
import '../../models/diagnostic.dart';
import '../../models/received_bundle.dart';
import '../../models/revision_loyer.dart';
import '../../models/sci.dart';
import '../../models/user_profile.dart';
import '../constants.dart';
import 'secure_key_store.dart';

/// Point d'entrée du stockage local chiffré (Hive + AES-256).
class LocalDatabase {
  static bool _initialized = false;
  static late Box<UserProfile> _userBox;
  static late Box<Logement> _logementsBox;
  static late Box<Locataire> _locatairesBox;
  static late Box<EtatDesLieux> _etatDesLieuxBox;
  static late Box<Quittance> _quittancesBox;
  static late Box<ReceivedBundle> _receivedBundlesBox;
  static late Box<PlanLogement> _plansLogementBox;
  static late Box<Depense> _depensesBox;
  static late Box<CreditImmobilier> _creditsImmobiliersBox;
  static late Box<String> _customExpenseCategoriesBox;
  static late Box<RevisionLoyer> _revisionsLoyerBox;
  static late Box<FiscalSettings> _fiscalSettingsBox;
  static late Box<SCI> _scisBox;
  static late Box<ContratBail> _contratsBailBox;
  static late Box<Avenant> _avenantsBox;
  static late Box<Diagnostic> _diagnosticsBox;
  static late Box<BailTemplate> _bailTemplatesBox;
  static late Box<String> _settingsBox;

  static Box<UserProfile> get userBox {
    _ensureInit();
    return _userBox;
  }

  static Box<Logement> get logementsBox {
    _ensureInit();
    return _logementsBox;
  }

  static Box<Locataire> get locatairesBox {
    _ensureInit();
    return _locatairesBox;
  }

  static Box<EtatDesLieux> get etatDesLieuxBox {
    _ensureInit();
    return _etatDesLieuxBox;
  }

  static Box<Quittance> get quittancesBox {
    _ensureInit();
    return _quittancesBox;
  }

  static Box<ReceivedBundle> get receivedBundlesBox {
    _ensureInit();
    return _receivedBundlesBox;
  }

  static Box<PlanLogement> get plansLogementBox {
    _ensureInit();
    return _plansLogementBox;
  }

  static Box<Depense> get depensesBox {
    _ensureInit();
    return _depensesBox;
  }

  static Box<CreditImmobilier> get creditsImmobiliersBox {
    _ensureInit();
    return _creditsImmobiliersBox;
  }

  static Box<String> get customExpenseCategoriesBox {
    _ensureInit();
    return _customExpenseCategoriesBox;
  }

  static Box<RevisionLoyer> get revisionsLoyerBox {
    _ensureInit();
    return _revisionsLoyerBox;
  }

  static Box<FiscalSettings> get fiscalSettingsBox {
    _ensureInit();
    return _fiscalSettingsBox;
  }

  static Box<SCI> get scisBox {
    _ensureInit();
    return _scisBox;
  }

  static Box<ContratBail> get contratsBailBox {
    _ensureInit();
    return _contratsBailBox;
  }

  static Box<Avenant> get avenantsBox {
    _ensureInit();
    return _avenantsBox;
  }

  static Box<Diagnostic> get diagnosticsBox {
    _ensureInit();
    return _diagnosticsBox;
  }

  static Box<BailTemplate> get bailTemplatesBox {
    _ensureInit();
    return _bailTemplatesBox;
  }

  static Box<String> get settingsBox {
    _ensureInit();
    return _settingsBox;
  }

  static void _ensureInit() {
    if (!_initialized) {
      throw StateError('LocalDatabase.init() doit être appelé au démarrage.');
    }
  }

  static Future<void> init() async {
    if (_initialized) return;

    await Hive.initFlutter();

    // Avant toute ouverture de box : appliquer une restauration éventuellement
    // demandée, puis créer une sauvegarde de sécurité si l'app a changé de
    // version (les fichiers .hive sont alors au repos). Ne doit JAMAIS bloquer
    // le démarrage.
    String? docsPath;
    try {
      docsPath = (await getApplicationDocumentsDirectory()).path;
      await _applyPendingRestore(docsPath);
      await snapshotBeforeUpgrade(
        dirPath: docsPath,
        currentVersion: AppConstants.appVersion,
      );
    } catch (_) {/* tolérant aux erreurs : la sécurité ne doit pas casser l'app */}

    _registerAdapter(UserProfileAdapter());
    _registerAdapter(LogementAdapter());
    _registerAdapter(LocataireAdapter());
    _registerAdapter(EtatDesLieuxAdapter());
    _registerAdapter(PieceAdapter());
    _registerAdapter(ElementPieceAdapter());
    _registerAdapter(QuittanceAdapter());
    _registerAdapter(ReceivedBundleAdapter());
    _registerAdapter(PlanLogementAdapter());
    _registerAdapter(RoomShapeAdapter());
    _registerAdapter(PlanAnnotationAdapter());
    _registerAdapter(WallPhotoAdapter());
    _registerAdapter(FreeWallAdapter());
    _registerAdapter(DepenseAdapter());
    _registerAdapter(CreditImmobilierAdapter());
    _registerAdapter(RevisionLoyerAdapter());
    _registerAdapter(FiscalSettingsAdapter());
    _registerAdapter(SCIAdapter());
    _registerAdapter(ContratBailAdapter());
    _registerAdapter(AvenantAdapter());
    _registerAdapter(DiagnosticAdapter());
    _registerAdapter(BailTemplateAdapter());

    final encryptionKey = await SecureKeyStore.getOrCreateEncryptionKey();
    final cipher = HiveAesCipher(encryptionKey);

    _userBox = await Hive.openBox<UserProfile>(
      AppConstants.userProfileBox,
      encryptionCipher: cipher,
    );
    _logementsBox = await Hive.openBox<Logement>(
      AppConstants.logementsBox,
      encryptionCipher: cipher,
    );
    _locatairesBox = await Hive.openBox<Locataire>(
      AppConstants.locatairesBox,
      encryptionCipher: cipher,
    );
    _etatDesLieuxBox = await Hive.openBox<EtatDesLieux>(
      AppConstants.etatDesLieuxBox,
      encryptionCipher: cipher,
    );
    _quittancesBox = await Hive.openBox<Quittance>(
      AppConstants.quittancesBox,
      encryptionCipher: cipher,
    );
    _receivedBundlesBox = await Hive.openBox<ReceivedBundle>(
      AppConstants.receivedBundlesBox,
      encryptionCipher: cipher,
    );
    _plansLogementBox = await Hive.openBox<PlanLogement>(
      AppConstants.plansLogementBox,
      encryptionCipher: cipher,
    );
    _depensesBox = await Hive.openBox<Depense>(
      AppConstants.depensesBox,
      encryptionCipher: cipher,
    );
    _creditsImmobiliersBox = await Hive.openBox<CreditImmobilier>(
      AppConstants.creditsImmobiliersBox,
      encryptionCipher: cipher,
    );
    _customExpenseCategoriesBox = await Hive.openBox<String>(
      AppConstants.customExpenseCategoriesBox,
      encryptionCipher: cipher,
    );
    _revisionsLoyerBox = await Hive.openBox<RevisionLoyer>(
      AppConstants.revisionsLoyerBox,
      encryptionCipher: cipher,
    );
    _fiscalSettingsBox = await Hive.openBox<FiscalSettings>(
      AppConstants.fiscalSettingsBox,
      encryptionCipher: cipher,
    );
    _scisBox = await Hive.openBox<SCI>(
      AppConstants.scisBox,
      encryptionCipher: cipher,
    );
    _contratsBailBox = await Hive.openBox<ContratBail>(
      AppConstants.contratsBailBox,
      encryptionCipher: cipher,
    );
    _avenantsBox = await Hive.openBox<Avenant>(
      AppConstants.avenantsBox,
      encryptionCipher: cipher,
    );
    _diagnosticsBox = await Hive.openBox<Diagnostic>(
      AppConstants.diagnosticsBox,
      encryptionCipher: cipher,
    );
    _bailTemplatesBox = await Hive.openBox<BailTemplate>(
      AppConstants.bailTemplatesBox,
      encryptionCipher: cipher,
    );
    _settingsBox = await Hive.openBox<String>(
      AppConstants.settingsBox,
      encryptionCipher: cipher,
    );

    _initialized = true;

    await _migrateContratsLocataireToLogement();

    // Migrations passées sans encombre → on mémorise la version courante.
    if (docsPath != null) {
      try {
        await recordCurrentVersion(docsPath, AppConstants.appVersion);
      } catch (_) {/* non bloquant */}
    }
  }

  // ───────────────────── Sauvegardes de sécurité (avant MAJ) ─────────────────

  static const String _versionMarker = '.adda_data_version';
  static const String _pendingRestoreMarker = '.adda_pending_restore';
  static const String _snapshotsDir = 'pre_update_backups';

  /// Copie les fichiers Hive (.hive) dans un dossier horodaté AVANT migration,
  /// si la version stockée diffère de [currentVersion]. Ne met PAS à jour le
  /// marqueur de version (fait seulement après des migrations réussies).
  /// Statique et sans I/O cachée pour être testable directement.
  static Future<Directory?> snapshotBeforeUpgrade({
    required String dirPath,
    required String currentVersion,
    String? nowStamp,
    int keepLast = 3,
  }) async {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return null;
    final marker = File('$dirPath/$_versionMarker');
    final last = marker.existsSync() ? marker.readAsStringSync().trim() : null;
    if (last == null || last == currentVersion) return null;

    final hiveFiles = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.hive'))
        .toList();
    if (hiveFiles.isEmpty) return null;

    final stamp = nowStamp ??
        DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    final snapDir = Directory('$dirPath/$_snapshotsDir/${stamp}__v$last');
    await snapDir.create(recursive: true);
    for (final f in hiveFiles) {
      await f.copy('${snapDir.path}/${f.uri.pathSegments.last}');
    }
    await _prunePreUpdateSnapshots(dirPath, keepLast);
    return snapDir;
  }

  static Future<void> _prunePreUpdateSnapshots(
      String dirPath, int keepLast) async {
    final root = Directory('$dirPath/$_snapshotsDir');
    if (!root.existsSync()) return;
    final snaps = root.listSync().whereType<Directory>().toList()
      ..sort((a, b) => b.path.compareTo(a.path)); // horodatage ISO → récent d'abord
    for (var i = keepLast; i < snaps.length; i++) {
      try {
        await snaps[i].delete(recursive: true);
      } catch (_) {/* non critique */}
    }
  }

  /// Mémorise [version] comme dernière version ayant démarré avec succès.
  static Future<void> recordCurrentVersion(
      String dirPath, String version) async {
    await File('$dirPath/$_versionMarker').writeAsString(version, flush: true);
  }

  /// Sauvegardes de sécurité disponibles (de la plus récente à la plus ancienne).
  static Future<List<Directory>> listPreUpdateSnapshots() async {
    if (!_initialized) return [];
    final docs = await getApplicationDocumentsDirectory();
    final root = Directory('${docs.path}/$_snapshotsDir');
    if (!root.existsSync()) return [];
    return root.listSync().whereType<Directory>().toList()
      ..sort((a, b) => b.path.compareTo(a.path));
  }

  /// Programme la restauration d'un snapshot : elle sera appliquée en sécurité
  /// au PROCHAIN démarrage (avant l'ouverture des box), puis l'app redémarre.
  static Future<void> requestRestore(String snapshotDirPath) async {
    final docs = await getApplicationDocumentsDirectory();
    await File('${docs.path}/$_pendingRestoreMarker')
        .writeAsString(snapshotDirPath, flush: true);
  }

  /// Applique une restauration programmée : recopie les .hive du snapshot
  /// par-dessus les fichiers vivants (boxes encore fermées), puis efface le
  /// marqueur. Sûr car exécuté avant toute ouverture de box.
  static Future<void> _applyPendingRestore(String dirPath) async {
    final marker = File('$dirPath/$_pendingRestoreMarker');
    if (!marker.existsSync()) return;
    final snapPath = marker.readAsStringSync().trim();
    final snapDir = Directory(snapPath);
    if (snapDir.existsSync()) {
      for (final f in snapDir.listSync().whereType<File>()) {
        if (!f.path.endsWith('.hive')) continue;
        final name = f.uri.pathSegments.last;
        await f.copy('$dirPath/$name');
      }
    }
    try {
      await marker.delete();
    } catch (_) {}
  }

  /// Migration : les contrats de bail importés sur la fiche locataire sont
  /// désormais rattachés au logement (puisque le bail couvre tout le foyer).
  /// Les chemins existants sont déplacés vers les logements correspondants,
  /// puis la liste locataire est vidée.
  static Future<void> _migrateContratsLocataireToLogement() async {
    for (final locataire in _locatairesBox.values.toList()) {
      if (locataire.contratBailPaths.isEmpty) continue;
      final logementIds = locataire.logementIds;
      if (logementIds.isEmpty) continue;
      for (final logementId in logementIds) {
        final logement = _logementsBox.get(logementId);
        if (logement == null) continue;
        for (final path in locataire.contratBailPaths) {
          if (!logement.contratBailPaths.contains(path)) {
            logement.contratBailPaths.add(path);
          }
        }
        await _logementsBox.put(logement.id, logement);
      }
      locataire.contratBailPaths = <String>[];
      await _locatairesBox.put(locataire.id, locataire);
    }
  }

  static void _registerAdapter<T>(TypeAdapter<T> adapter) {
    if (!Hive.isAdapterRegistered(adapter.typeId)) {
      Hive.registerAdapter(adapter);
    }
  }

  /// Détruit toutes les données locales et la clé. Irréversible.
  static Future<void> wipeEverything() async {
    if (_initialized) {
      await _userBox.clear();
      await _logementsBox.clear();
      await _locatairesBox.clear();
      await _etatDesLieuxBox.clear();
      await _quittancesBox.clear();
      await _receivedBundlesBox.clear();
      await _plansLogementBox.clear();
      await _depensesBox.clear();
      await _creditsImmobiliersBox.clear();
      await _customExpenseCategoriesBox.clear();
      await _revisionsLoyerBox.clear();
      await _fiscalSettingsBox.clear();
      await _scisBox.clear();
      await _contratsBailBox.clear();
      await _avenantsBox.clear();
      await _diagnosticsBox.clear();
      await _bailTemplatesBox.clear();
      await _settingsBox.clear();
      await _userBox.close();
      await _logementsBox.close();
      await _locatairesBox.close();
      await _etatDesLieuxBox.close();
      await _quittancesBox.close();
      await _receivedBundlesBox.close();
      await _plansLogementBox.close();
      await _depensesBox.close();
      await _creditsImmobiliersBox.close();
      await _customExpenseCategoriesBox.close();
      await _revisionsLoyerBox.close();
      await _fiscalSettingsBox.close();
      await _scisBox.close();
      await _contratsBailBox.close();
      await _avenantsBox.close();
      await _diagnosticsBox.close();
      await _bailTemplatesBox.close();
      await _settingsBox.close();
      _initialized = false;
    }
    await Hive.deleteBoxFromDisk(AppConstants.userProfileBox);
    await Hive.deleteBoxFromDisk(AppConstants.logementsBox);
    await Hive.deleteBoxFromDisk(AppConstants.locatairesBox);
    await Hive.deleteBoxFromDisk(AppConstants.etatDesLieuxBox);
    await Hive.deleteBoxFromDisk(AppConstants.quittancesBox);
    await Hive.deleteBoxFromDisk(AppConstants.receivedBundlesBox);
    await Hive.deleteBoxFromDisk(AppConstants.plansLogementBox);
    await Hive.deleteBoxFromDisk(AppConstants.depensesBox);
    await Hive.deleteBoxFromDisk(AppConstants.creditsImmobiliersBox);
    await Hive.deleteBoxFromDisk(AppConstants.customExpenseCategoriesBox);
    await Hive.deleteBoxFromDisk(AppConstants.revisionsLoyerBox);
    await Hive.deleteBoxFromDisk(AppConstants.fiscalSettingsBox);
    await Hive.deleteBoxFromDisk(AppConstants.scisBox);
    await Hive.deleteBoxFromDisk(AppConstants.contratsBailBox);
    await Hive.deleteBoxFromDisk(AppConstants.avenantsBox);
    await Hive.deleteBoxFromDisk(AppConstants.diagnosticsBox);
    await Hive.deleteBoxFromDisk(AppConstants.bailTemplatesBox);
    await Hive.deleteBoxFromDisk(AppConstants.settingsBox);
    await SecureKeyStore.deleteKey();
    // Fichiers utilisateur stockés HORS Hive (photos, PDF, justificatifs,
    // snapshots…) : la suppression des boxes ne les touche pas. On purge le
    // périmètre connu pour que « tout effacer » couvre réellement TOUTES les
    // données personnelles (conformité Apple 5.1.1(v)).
    try {
      final docsPath = (await getApplicationDocumentsDirectory()).path;
      await wipeUserFiles(docsPath);
    } catch (_) {/* répertoire documents injoignable : non bloquant */}
    if (Platform.isAndroid) {
      // Sur Android, les backups reçus vivent sous le stockage externe.
      try {
        final ext = await getExternalStorageDirectory();
        if (ext != null) await wipeUserFiles(ext.path);
      } catch (_) {/* non bloquant */}
    }
  }

  /// Sous-dossiers de fichiers utilisateur stockés **hors Hive**, relatifs au
  /// répertoire documents de l'app (et au stockage externe Android pour les
  /// backups reçus). [wipeEverything] les supprime pour que la réinitialisation
  /// et la suppression de compte effacent *toutes* les données personnelles —
  /// pas seulement les boxes Hive.
  ///
  /// ⚠️ **À garder synchronisé** : toute nouvelle catégorie de fichier rangée
  /// sous documents/ DOIT être ajoutée ici, sinon des données (noms, adresses,
  /// signatures de locataires…) survivraient à la suppression de compte.
  /// Couvert par `test/account_deletion_test.dart`.
  static const List<String> userFileDirs = [
    'photos', // PhotoStorage : photos d'état des lieux
    'contrats', // ContratStorage : PDF de baux importés
    'plans', // PlanLogementService : plans + murs
    'diagnostics', // diagnostics importés (DPE…)
    'edl_exports', // PDF d'états des lieux générés
    'exports_compta', // ComptaExportService : exports CSV
    'expense_justifs', // DepenseService._justifsDir : justificatifs de dépenses
    _snapshotsDir, // pre_update_backups : copies .hive d'avant migration
    'ADDA Bailleur document', // ReceivedBackupsService : bundles reçus
    'sauvegardes_recues', // ancien dossier de backups reçus (legacy)
  ];

  /// Supprime, sous [dirPath], tous les dossiers listés dans [userFileDirs].
  /// **Best-effort** : un dossier absent ou verrouillé n'interrompt pas la
  /// purge des autres. Exposé pour les tests (cf. [wipeEverything]).
  static Future<void> wipeUserFiles(String dirPath) async {
    for (final name in userFileDirs) {
      try {
        final dir = Directory('$dirPath/$name');
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      } catch (_) {/* fichier/dossier non critique : on continue */}
    }
  }
}
