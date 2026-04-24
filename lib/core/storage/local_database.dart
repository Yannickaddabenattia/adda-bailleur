import 'package:hive_ce_flutter/hive_flutter.dart';

import '../../models/element_piece.dart';
import '../../models/etat_des_lieux.dart';
import '../../models/locataire.dart';
import '../../models/logement.dart';
import '../../models/piece.dart';
import '../../models/quittance.dart';
import '../../models/received_bundle.dart';
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

    _initialized = true;
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
      await _userBox.close();
      await _logementsBox.close();
      await _locatairesBox.close();
      await _etatDesLieuxBox.close();
      await _quittancesBox.close();
      await _receivedBundlesBox.close();
      _initialized = false;
    }
    await Hive.deleteBoxFromDisk(AppConstants.userProfileBox);
    await Hive.deleteBoxFromDisk(AppConstants.logementsBox);
    await Hive.deleteBoxFromDisk(AppConstants.locatairesBox);
    await Hive.deleteBoxFromDisk(AppConstants.etatDesLieuxBox);
    await Hive.deleteBoxFromDisk(AppConstants.quittancesBox);
    await Hive.deleteBoxFromDisk(AppConstants.receivedBundlesBox);
    await SecureKeyStore.deleteKey();
  }
}
