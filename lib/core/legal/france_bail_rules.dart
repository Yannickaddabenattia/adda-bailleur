import '../../models/logement.dart' show DpeClasse;

/// Règles légales **françaises** de génération des documents de location
/// (décence énergétique, cumul caution/GLI). Périmètre France uniquement.
///
/// Chaque message d'erreur cite sa source (anti-réversion).
class FranceBailRules {
  const FranceBailRules._();

  // ─── Textes légaux de l'acte de caution (VERBATIM Légifrance) ─────────────
  // L'art. 22-1 (v. 01/01/2022, ord. 2021-1192) ne contient plus de formule de
  // mention propre : il RENVOIE à l'art. 2297 du Code civil.

  /// Titre de la zone que la caution remplit elle-même.
  static const String cautionMentionTitre =
      'Mention prévue par l\'article 2297 du Code civil '
      '(à apposer par la caution elle-même)';

  /// Consigne **verbatim** (art. 2297, al. 1er C. civ.) affichée AU-DESSUS de la
  /// zone vide ; la caution recopie elle-même cette mention (rien n'est
  /// pré-rempli dans la zone, à peine de nullité).
  static const String cautionMention2297 =
      'À peine de nullité de son engagement, la caution personne physique '
      'appose elle-même la mention qu\'elle s\'engage en qualité de caution à '
      'payer au créancier ce que lui doit le débiteur en cas de défaillance de '
      'celui-ci, dans la limite d\'un montant en principal et accessoires '
      'exprimé en toutes lettres et en chiffres. En cas de différence, le '
      'cautionnement vaut pour la somme écrite en toutes lettres.';

  /// Avant-dernier alinéa de l'art. 22-1 (loi n° 89-462, v. 01/01/2022),
  /// **verbatim** — à reproduire dans l'acte (formalité prescrite à peine de
  /// nullité par le dernier alinéa de l'art. 22-1).
  static const String cautionResiliationAlinea =
      'Lorsque le cautionnement d\'obligations résultant d\'un contrat de '
      'location conclu en application du présent titre ne comporte aucune '
      'indication de durée ou lorsque la durée du cautionnement est stipulée '
      'indéterminée, la caution peut le résilier unilatéralement. La '
      'résiliation prend effet au terme du contrat de location, qu\'il s\'agisse '
      'du contrat initial ou d\'un contrat reconduit ou renouvelé, au cours '
      'duquel le bailleur reçoit notification de la résiliation.';

  /// **Blocage de génération de bail si classe DPE G** pour une signature à
  /// partir du 01/01/2025 (logement interdit à la location).
  /// 📚 loi n° 2021-1104 du 22/08/2021 (Climat et Résilience) ; art. L. 173-1-1
  /// CCH (décence énergétique). Retourne un message bloquant, sinon `null`.
  static String? bailDpeGError(DpeClasse? dpeClasse, DateTime signature) {
    if (dpeClasse == DpeClasse.g &&
        !signature.isBefore(DateTime(2025, 1, 1))) {
      return 'Génération bloquée : un logement classé G est interdit à la '
          'location depuis le 01/01/2025 (décence énergétique — loi n° 2021-1104, '
          'art. L. 173-1-1 CCH).';
    }
    return null;
  }

  /// Avertissement non bloquant : classe F (interdite dès le 01/01/2028),
  /// E (dès le 01/01/2034) ou classe inconnue (`null`).
  /// 📚 loi n° 2021-1104 (calendrier de décence énergétique).
  static String? bailDpeWarning(DpeClasse? dpeClasse) {
    if (dpeClasse == null) {
      return 'Classe DPE inconnue — à renseigner (impacte le gel des loyers et '
          'la décence énergétique).';
    }
    if (dpeClasse == DpeClasse.f) {
      return 'Logement classé F : interdit à la location dès le 01/01/2028.';
    }
    if (dpeClasse == DpeClasse.e) {
      return 'Logement classé E : interdit à la location dès le 01/01/2034.';
    }
    return null;
  }

  /// **Cumul caution + assurance loyers impayés (GLI) interdit**, sauf locataire
  /// étudiant ou apprenti.
  /// 📚 loi n° 89-462, art. 22-1, al. 1er. Retourne un message bloquant, sinon
  /// `null`.
  static String? cautionGliError({
    required bool assuranceLoyersImpayes,
    required bool locataireEtudiantApprenti,
  }) {
    if (assuranceLoyersImpayes && !locataireEtudiantApprenti) {
      return 'Cumul interdit : une assurance loyers impayés (GLI) ne peut se '
          'cumuler avec un cautionnement, sauf locataire étudiant ou apprenti '
          '(loi n° 89-462, art. 22-1, al. 1er).';
    }
    return null;
  }

  /// **Encadrement des loyers (A5)** — en zone d'encadrement, le loyer hors
  /// charges ne peut excéder le **loyer de référence majoré** (€/m² × surface),
  /// sauf complément de loyer justifié. Retourne un **avertissement non
  /// bloquant** si le loyer dépasse ce plafond + complément, sinon `null`.
  /// 📚 loi n° 89-462, art. 140 (zones d'encadrement) ; art. 17 & 25-9.
  static String? encadrementDepassementWarning({
    required bool zoneEncadrement,
    required double loyerHC,
    required double surfaceM2,
    double? loyerReferenceMajore,
    double? complementLoyer,
  }) {
    if (!zoneEncadrement ||
        loyerReferenceMajore == null ||
        loyerReferenceMajore <= 0 ||
        surfaceM2 <= 0) {
      return null;
    }
    final plafond = loyerReferenceMajore * surfaceM2 + (complementLoyer ?? 0);
    if (loyerHC > plafond + 0.01) {
      return 'Le loyer hors charges saisi dépasse le plafond autorisé en zone '
          'd\'encadrement (loyer de référence majoré × surface'
          '${complementLoyer != null && complementLoyer > 0 ? ' + complément' : ''}). '
          'Vérifiez le montant ou justifiez un complément de loyer '
          '(loi n° 89-462, art. 140).';
    }
    return null;
  }
}
