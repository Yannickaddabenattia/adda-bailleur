import 'package:flutter/foundation.dart';

import '../core/constants.dart';
import '../core/storage/local_database.dart';
import '../models/user_profile.dart';
import '../models/user_role.dart';
import 'auto_backup_service.dart';
import 'master_key_service.dart';

/// Exception levée si on tente de modifier un profil déjà figé.
class ImmutableProfileException implements Exception {
  final String message;
  ImmutableProfileException(this.message);
  @override
  String toString() => 'ImmutableProfileException: $message';
}

/// Exception levée si les données stockées ont été altérées.
class ProfileIntegrityException implements Exception {
  final String message;
  ProfileIntegrityException(this.message);
  @override
  String toString() => 'ProfileIntegrityException: $message';
}

/// Service central pour le profil utilisateur.
///
/// Garantit l'immuabilité des 4 champs (rôle, prénom, nom, email)
/// après leur première validation.
class UserService extends ChangeNotifier {
  UserProfile? _current;
  UserProfile? get current => _current;
  bool get hasProfile => _current != null;

  /// Charge le profil depuis le stockage chiffré au démarrage.
  Future<void> load() async {
    final stored = LocalDatabase.userBox.get(AppConstants.userProfileKey);
    if (stored == null) {
      _current = null;
      notifyListeners();
      return;
    }
    if (!stored.verifyIntegrity()) {
      throw ProfileIntegrityException(
        'Le profil stocké a été altéré. Hash d\'intégrité invalide.',
      );
    }
    _current = stored;
    notifyListeners();
  }

  /// Crée le profil initial. **Une seule fois.** Toute tentative
  /// ultérieure lèvera [ImmutableProfileException].
  Future<UserProfile> createInitialProfile({
    required UserRole role,
    required String firstName,
    required String lastName,
    required String email,
  }) async {
    if (_current != null) {
      throw ImmutableProfileException(
        'Un profil existe déjà. Les champs rôle/nom/email sont figés.',
      );
    }
    final profile = UserProfile.create(
      role: role,
      firstName: firstName,
      lastName: lastName,
      email: email,
    );
    await LocalDatabase.userBox.put(AppConstants.userProfileKey, profile);
    _current = profile;
    notifyListeners();
    return profile;
  }

  /// Réinitialise complètement l'application (efface le profil et la clé).
  /// À utiliser avec prudence — aucune récupération possible sans sauvegarde.
  Future<void> factoryReset() async {
    await LocalDatabase.wipeEverything();
    _current = null;
    notifyListeners();
  }

  /// **Suppression définitive du compte** (conformité Apple Guideline
  /// 5.1.1(v)). L'app étant *local-first* (pas de Firebase/serveur), « le
  /// compte » = le profil local + le mot de passe maître + les sauvegardes
  /// chiffrées déposées dans le cloud. Cette méthode efface tout, sans
  /// possibilité de récupération :
  ///
  /// 1. **Cloud** : supprime les sauvegardes accessibles dans le dossier lié
  ///    puis délie le dossier (passphrase du trousseau incluse).
  /// 2. **Mot de passe maître** : effacé du trousseau + des réglages.
  /// 3. **Local** : efface profil + toutes les données + clé de chiffrement
  ///    (`wipeEverything`), puis ré-initialise une base vierge pour permettre
  ///    un nouvel onboarding.
  ///
  /// Les étapes cloud/mot de passe sont **best-effort** (ne bloquent pas la
  /// suppression si le cloud est injoignable) et s'exécutent AVANT le wipe
  /// (elles lisent `settingsBox`/le trousseau). La redirection vers l'écran
  /// d'accueil est faite par l'appelant (le profil passe à `null`).
  Future<void> deleteAccount({
    MasterKeyService? masterKey,
    AutoBackupService? autoBackup,
  }) async {
    // 1. Données cloud.
    if (autoBackup != null) {
      try {
        await autoBackup.deleteAllBackups();
      } catch (_) {/* dossier injoignable : non bloquant */}
      try {
        await autoBackup.disable();
      } catch (_) {/* non bloquant */}
    }
    // 2. Mot de passe maître (trousseau + réglages) — avant le wipe.
    if (masterKey != null) {
      try {
        await masterKey.clear();
      } catch (_) {/* non bloquant */}
    }
    // 3. Stockage local : tout effacer, puis repartir d'une base vierge.
    await LocalDatabase.wipeEverything();
    await LocalDatabase.init();
    _current = null;
    notifyListeners();
  }
}
