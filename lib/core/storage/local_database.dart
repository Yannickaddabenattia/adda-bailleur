import 'package:hive_ce_flutter/hive_flutter.dart';

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
  }
}
