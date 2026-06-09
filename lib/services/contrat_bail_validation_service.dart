import '../core/diagnostic_obligations.dart';
import '../models/contrat_bail.dart';
import '../models/diagnostic.dart';
import '../models/logement.dart';

/// Validation métier centralisée d'un contrat de bail.
///
/// [validate] retourne la liste des problèmes **bloquants** (liste vide = bail
/// complet et conforme). Cette validation est utilisée à deux endroits :
///  - le formulaire de création/édition (pour guider la saisie) ;
///  - en **verrou dur** avant la génération du PDF (un bail incomplet ne doit
///    jamais produire de PDF dégradé).
class ContratBailValidation {
  /// Équipements obligatoires d'un logement meublé (décret n°2015-981).
  /// Doit rester synchronisé avec la liste du formulaire de bail.
  static const List<String> equipementsMeublesObligatoires = [
    'Literie (lit + matelas)',
    'Table et sièges',
    'Étagères de rangement',
    'Luminaires',
    'Plaques de cuisson',
    'Four ou micro-ondes',
    'Réfrigérateur + congélateur',
    'Ustensiles de cuisine',
    'Évier avec robinetterie',
    'Volets ou rideaux occultants (chambre)',
  ];

  /// Renvoie la liste des problèmes bloquants empêchant la génération du PDF.
  static List<String> validate(ContratBail b) {
    final errors = <String>[];

    if (b.locataireIds.isEmpty) {
      errors.add('Au moins un locataire doit être rattaché au bail.');
    }
    if (b.adresseLogement.trim().isEmpty) {
      errors.add('L\'adresse du logement est obligatoire.');
    }
    if (b.loyerHC <= 0) {
      errors.add('Le loyer hors charges doit être supérieur à 0 €.');
    }
    if (b.charges < 0) {
      errors.add('Les charges ne peuvent pas être négatives.');
    }
    if (b.jourEcheance < 1 || b.jourEcheance > 28) {
      errors.add('Le jour de paiement doit être compris entre 1 et 28.');
    }

    // Dépôt de garantie : plafond légal (2 mois vide / 1 mois sinon).
    final plafond = b.loyerHC * b.type.plafondDepotMois;
    if (b.depotGarantie < 0) {
      errors.add('Le dépôt de garantie ne peut pas être négatif.');
    } else if (b.loyerHC > 0 && b.depotGarantie > plafond + 0.01) {
      errors.add(
        'Le dépôt de garantie (${b.depotGarantie.toStringAsFixed(2)} €) dépasse '
        'le plafond légal de ${b.type.plafondDepotMois} mois de loyer '
        '(${plafond.toStringAsFixed(2)} €).',
      );
    }

    // Bailleur société : raison sociale + SIRET obligatoires.
    if (b.bailleurEstSociete) {
      if ((b.bailleurRaisonSociale ?? '').trim().isEmpty) {
        errors.add('Bailleur société : la raison sociale est obligatoire.');
      }
      if ((b.bailleurSiret ?? '').trim().isEmpty) {
        errors.add('Bailleur société : le SIRET est obligatoire.');
      }
    }

    // Attestation d'assurance habitation du locataire (obligatoire).
    if (!b.attestationAssurance) {
      errors.add(
        'L\'attestation d\'assurance habitation du locataire est obligatoire.',
      );
    }

    // Surface habitable obligatoire (loi du 6 juillet 1989) — hors saisonnier.
    if (b.type != BailType.saisonnier && b.surfaceM2 <= 0) {
      errors.add('La surface habitable est obligatoire (doit être > 0 m²).');
    }

    // Liste des meubles obligatoire si le bail est meublé.
    if (b.type == BailType.meuble) {
      final manquants = equipementsMeublesObligatoires
          .where((e) => b.equipementsMeuble[e] != true)
          .toList();
      if (manquants.isNotEmpty) {
        errors.add(
          'Bail meublé : équipements obligatoires non cochés — '
          '${manquants.join(', ')}.',
        );
      }
    }

    return errors;
  }

  /// Vrai si le bail est complet (aucun problème bloquant).
  static bool isComplete(ContratBail b) => validate(b).isEmpty;

  /// Validation complète incluant les diagnostics conditionnels (nécessite le
  /// logement et la liste de ses diagnostics).
  static List<String> validateFull(
    ContratBail b, {
    Logement? logement,
    List<Diagnostic> diagnostics = const [],
  }) {
    final errors = validate(b);
    if (logement != null) {
      errors.addAll(DiagnosticObligations.problemes(logement, diagnostics));
    }
    return errors;
  }
}
