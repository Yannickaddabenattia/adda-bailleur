import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/user_role.dart';
import '../../services/auto_backup_service.dart';
import '../../services/master_key_service.dart';
import '../../services/user_service.dart';
import '../onboarding/user_info_screen.dart';

/// Parcours de suppression de compte (Apple Guideline 5.1.1(v)) : confirmation
/// explicite → suppression irréversible → retour à l'onboarding. App
/// *local-first* : efface profil + données + mot de passe maître + sauvegardes
/// cloud accessibles (cf. [UserService.deleteAccount]).
///
/// **Source unique** réutilisée par Réglages > COMPTE et par l'écran
/// Sauvegarde (accès rapide), pour garantir un parcours identique.
Future<void> confirmDeleteAccount(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Supprimer mon compte ?'),
      content: const Text(
        'Cette action est définitive et irréversible. Elle effacera :\n\n'
        '• votre profil ;\n'
        '• tous vos biens, locataires, quittances, états des lieux et '
        'documents ;\n'
        '• votre mot de passe maître ;\n'
        '• les sauvegardes chiffrées accessibles dans votre dossier cloud lié.\n\n'
        'Aucune récupération ne sera possible.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Annuler'),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: AppColors.error),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Supprimer définitivement'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final userService = context.read<UserService>();
  final masterKey = context.read<MasterKeyService>();
  final autoBackup = context.read<AutoBackupService>();
  final navigator = Navigator.of(context, rootNavigator: true);
  final messenger = ScaffoldMessenger.of(context);

  // Indicateur de chargement (non annulable) pendant la suppression.
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  try {
    await userService.deleteAccount(
      masterKey: masterKey,
      autoBackup: autoBackup,
    );
    navigator.pop(); // ferme le chargement
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const UserInfoScreen(role: UserRole.proprietaire),
      ),
      (route) => false,
    );
  } catch (e) {
    navigator.pop(); // ferme le chargement
    messenger.showSnackBar(
      SnackBar(content: Text('Échec de la suppression : $e')),
    );
  }
}
