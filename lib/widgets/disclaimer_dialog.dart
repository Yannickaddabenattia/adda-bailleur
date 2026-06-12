import 'package:flutter/material.dart';

/// Texte **verbatim** de l'avertissement juridique affiché avant toute
/// génération de document légal. **Source unique** : ne jamais dupliquer ce
/// texte ailleurs — toute mise à jour se fait ici.
const String kDisclaimerText =
    'Les documents générés par ADDA Bailleur sont basés sur la législation '
    'française en vigueur au moment de la mise à jour de l\'application. Nous '
    'recommandons vivement de les faire vérifier par un professionnel du droit '
    'ou un expert-comptable avant leur signature ou utilisation, notamment en '
    'cas de changement légal ou fiscal récent non encore intégré à '
    'l\'application.';

/// Boîte de dialogue d'avertissement juridique, présentée **avant** la
/// génération d'un document (bail, état des lieux, quittance, acte de caution,
/// notice, etc.).
///
/// Utilisation :
/// ```dart
/// if (!await DisclaimerDialog.show(context)) return; // annulé → on ne génère pas
/// ```
class DisclaimerDialog extends StatelessWidget {
  const DisclaimerDialog({super.key});

  /// Affiche le dialog et retourne `true` si l'utilisateur a confirmé,
  /// `false` s'il a annulé (ou fermé le dialog).
  static Future<bool> show(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const DisclaimerDialog(),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Avertissement'),
      content: const SingleChildScrollView(
        child: Text(kDisclaimerText),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Annuler'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('J\'ai compris, continuer'),
        ),
      ],
    );
  }
}
