import '../../../models/country.dart';
import 'country_document_template.dart';

/// Documents légaux **Suisse** (bail d'habitation — droit fédéral uniforme).
///
/// 📚 Socle : Code des obligations (CO) art. 253-274g ; Ordonnance sur le bail
/// (OBLF, RS 221.213.11). Montants en **CHF**.
///
/// ⚠️ Toute valeur non vérifiée est un placeholder `[À VALIDER JURISTE — …]`.
class SwitzerlandDocuments {
  const SwitzerlandDocuments._();

  // ───────────────────────────── BAIL (C.7) ────────────────────────────────
  static const CountryDocumentTemplate lease = CountryDocumentTemplate(
    countryCode: 'ch',
    currencyCode: 'CHF',
    docType: 'bail',
    requiredFields: [
      RequiredField('canton', 'Canton'),
      RequiredField('modeAdaptation',
          'Mode d\'adaptation du loyer (référence / indexé / échelonné)'),
    ],
    sections: [
      LeaseSection(
        titre: '1. Parties',
        contenu:
            'Identité du bailleur et du (des) locataire(s). Le bail écrit n\'est '
            'pas légalement obligatoire (contrat consensuel) mais l\'application '
            'génère toujours un écrit.',
        source: '📚 CO art. 253. ✅',
      ),
      LeaseSection(
        titre: '2. Objet loué',
        contenu:
            'Désignation du logement, dépendances et état. Le bailleur délivre '
            'la chose dans un état approprié à l\'usage convenu.',
        source: '📚 CO art. 256 (délivrance). ✅',
      ),
      LeaseSection(
        titre: '3. Début, durée et congé',
        contenu:
            'Durée indéterminée ou fixe. Congé : préavis minimal de 3 mois pour '
            'un terme contractuel ou d\'usage local (habitation). Le congé du '
            'bailleur requiert la formule officielle cantonale, sous peine de '
            'nullité ; motivation sur demande.',
        source: '📚 CO art. 266c ✅ ; CO art. 266l ✅ ; CO art. 271-272. ✅',
      ),
      LeaseSection(
        titre: '4. Loyer et frais accessoires',
        contenu:
            'Loyer net en CHF. Frais accessoires à la charge du locataire '
            'seulement s\'ils sont convenus : acomptes (avec décompte) ou '
            'forfait ; en lister le détail.',
        source: '📚 CO art. 257a-257b ; OBLF art. 4-8. ✅',
      ),
      LeaseSection(
        titre: '5. Mode d\'adaptation du loyer',
        contenu:
            'Indiquer le mode retenu : (a) loyer adaptable selon le taux '
            'hypothécaire de référence (OFL) ; (b) bail indexé sur l\'IPC suisse '
            '— licite si durée minimale 5 ans ; (c) bail échelonné — durée '
            'minimale 3 ans, paliers fixés d\'avance en CHF, une augmentation '
            'par an maximum. Toute hausse unilatérale via formule officielle.',
        source:
            '📚 CO art. 269b (indexé ≥ 5 ans) ✅ ; CO art. 269c (échelonné '
            '≥ 3 ans) ✅ ; CO art. 269d / 270b (formule, contestation) ✅ ; '
            'OBLF art. 12a-16. ✅',
      ),
      LeaseSection(
        titre: '6. Garantie de loyer',
        contenu:
            'Garantie limitée à 3 mois de loyer net, déposée sur un compte '
            'bancaire au nom du locataire (ou assurance de garantie). Le '
            'bailleur doit faire valoir ses prétentions dans l\'année suivant '
            'la fin du bail, sinon le locataire peut exiger la libération.',
        source: '📚 CO art. 257e. ✅',
      ),
      LeaseSection(
        titre: '7. Loyer initial (formule officielle)',
        contenu:
            'Dans les cantons qui l\'imposent (pénurie), la formule officielle '
            'de notification du loyer initial est obligatoire (loyer précédent, '
            'taux de référence et IPC applicables depuis le 01/10/2025), sous '
            'peine de nullité partielle. [À VALIDER JURISTE — canton concerné par '
            'la formule officielle ; renvoi à la liste OFL (bwo.admin.ch)].',
        source: '📚 CO art. 270 al. 2 ✅ ; OBLF art. 19 ✅ ; révision OBLF 01/10/2025. ✅',
      ),
      LeaseSection(
        titre: '8. Sous-location',
        contenu:
            'La sous-location requiert le consentement du bailleur, qui ne peut '
            'la refuser que pour trois motifs limitativement énumérés.',
        source: '📚 CO art. 262. ✅',
      ),
      LeaseSection(
        titre: '9. Entretien et menus travaux',
        contenu:
            'Le locataire prend à sa charge les menus travaux de nettoyage et '
            'de réparation indispensables à l\'entretien normal de la chose '
            '(art. 259 CO, usage local) : interventions simples réalisables par '
            'une personne moyennement habile sans recours à un spécialiste (à '
            'titre indicatif, de l\'ordre de 150 à 200 CHF par intervention '
            'selon la jurisprudence). Les réparations nécessitant un spécialiste '
            'ou excédant ce cadre incombent au bailleur. Toute clause fixant un '
            'plafond contractuel supérieur (ex. 1 % du loyer annuel) est réputée '
            'non conforme.',
        source:
            '📚 CO art. 259 ; OBLF art. 5 ; ATF 142 III 557 '
            '(relecture fiduciaire recommandée — usage local par canton).',
      ),
      LeaseSection(
        titre: '10. Restitution et avis des défauts',
        contenu:
            'Restitution dans l\'état résultant d\'un usage conforme. Le '
            'locataire avise immédiatement le bailleur des défauts cachés '
            'découverts après la restitution.',
        source: '📚 CO art. 267-267a. ✅',
      ),
      LeaseSection(
        titre: '11. For et droit applicable',
        contenu:
            'Droit suisse, for au lieu de situation de l\'immeuble. La location '
            'd\'habitation est exclue de la TVA.',
        source: '📚 CO + LTVA art. 21 al. 2 ch. 21. ✅',
      ),
      LeaseSection(
        titre: '12. Signatures',
        contenu: 'Signature des parties, un exemplaire par partie.',
        source: '📚 pratique.',
      ),
    ],
  );

  // ──────────────────── ÉTAT DES LIEUX (C.5) ───────────────────────────────
  static const CountryDocumentTemplate edl = CountryDocumentTemplate(
    countryCode: 'ch',
    currencyCode: 'CHF',
    docType: 'edl',
    requiredFields: [],
    sections: [
      LeaseSection(
        titre: 'Cadre',
        contenu:
            'Protocoles d\'entrée et de sortie contradictoires (pratique '
            'standard, pas de formalisme fédéral détaillé). Signaler les défauts '
            'à l\'entrée ; aviser immédiatement les défauts cachés découverts '
            'après la restitution.',
        source: '📚 CO art. 256, 267-267a. ✅',
      ),
      LeaseSection(
        titre: 'Menus travaux',
        contenu:
            'Nettoyage et réparations courantes à la charge du locataire '
            '(interventions simples, de l\'ordre de 150 à 200 CHF selon la '
            'jurisprudence ; voir la clause d\'entretien du bail).',
        source: '📚 CO art. 259 ; ATF 142 III 557.',
      ),
    ],
  );

  // ─────────────────────── QUITTANCE (C.6) ─────────────────────────────────
  static const CountryDocumentTemplate quittance = CountryDocumentTemplate(
    countryCode: 'ch',
    currencyCode: 'CHF',
    docType: 'quittance',
    requiredFields: [],
    sections: [
      LeaseSection(
        titre: 'Quittance de loyer',
        contenu:
            'Parties, bien, période, loyer net et frais accessoires (CHF), '
            'date, mode de paiement, « pour acquit ». Le débiteur peut exiger '
            'une quittance pour tout paiement. Mention « TVA : sans objet » '
            '(location d\'habitation exclue de la TVA).',
        source: '📚 CO art. 88 ✅ ; LTVA art. 21 al. 2 ch. 21. ✅',
      ),
    ],
  );

  // ─── Contrat-cadre / RULV (force obligatoire cantonale) ───────────────────

  /// Date limite de force obligatoire des RULV (canton de Vaud).
  static const String rulvForceObligatoireJusquau = '2026-06-30';
  static final DateTime rulvDateLimite = DateTime(2026, 6, 30);

  /// Clause de renvoi aux **RULV** (« Dispositions paritaires romandes et règles
  /// et usages locatifs du canton de Vaud »), à insérer **uniquement si le bien
  /// est dans le canton de Vaud**.
  ///
  /// 📚 Arrêté du Conseil fédéral du 24/06/2020 (FF 2020 5585) : force
  /// obligatoire du 01/07/2020 au 30/06/2026 ; OFL bwo.admin.ch.
  /// ⚠️ Le **contrat-cadre romand** (GE/FR/NE/JU/Bas-Valais) est **caduc depuis
  /// le 30/06/2020** (force obligatoire non prorogée) → AUCUNE clause ni renvoi
  /// pour ces cantons (source d'ambiguïté juridique). Cf. FF 2014 5087/5095.
  static const LeaseSection rulvClause = LeaseSection(
    titre: 'Dispositions paritaires romandes (RULV) — canton de Vaud',
    contenu:
        'Le présent bail est soumis aux « Dispositions paritaires romandes et '
        'règles et usages locatifs du canton de Vaud » (RULV), de force '
        'obligatoire, annexées au présent bail (à joindre).',
    source:
        '📚 arrêté du Conseil fédéral du 24/06/2020 (FF 2020 5585) — force '
        'obligatoire du 01/07/2020 au 30/06/2026 ; OFL bwo.admin.ch.',
  );

  /// Sections du bail pour un [canton] : ajoute la clause RULV **si Vaud**,
  /// rien pour les autres cantons (contrat-cadre romand caduc).
  static List<LeaseSection> leaseSectionsFor(ChCanton? canton) => [
        ...lease.sections,
        if (canton == ChCanton.vd) rulvClause,
      ];

  /// `true` si les RULV sont encore de force obligatoire à la [date]. Au-delà
  /// du 30/06/2026, le renouvellement n'étant pas confirmé, l'app doit afficher
  /// « statut RULV à vérifier (bwo.admin.ch) » plutôt qu'affirmer l'obligation.
  static bool rulvEncoreObligatoire(DateTime date) =>
      !date.isAfter(rulvDateLimite);

  /// Tous les documents CH, par type.
  static const Map<String, CountryDocumentTemplate> all = {
    'bail': lease,
    'edl': edl,
    'quittance': quittance,
  };
}
