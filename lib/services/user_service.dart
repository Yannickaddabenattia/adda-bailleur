import 'package:flutter/foundation.dart';

import '../core/constants.dart';
import '../core/storage/local_database.dart';
import '../models/user_profile.dart';
import '../models/user_role.dart';

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
}
