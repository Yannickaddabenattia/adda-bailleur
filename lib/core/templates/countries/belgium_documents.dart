import 'country_document_template.dart';

/// Documents légaux **Belgique** (bail d'habitation — résidence principale).
///
/// 📚 Socle : compétence régionalisée 2018-2019 — Wallonie (décret 15/03/2018),
/// Bruxelles (ordonnance 27/07/2017, Code bruxellois du Logement art. 216 ss),
/// Flandre (Vlaams Woninghuurdecreet 09/11/2018, baux dès 01/01/2019) ; socle
/// fédéral antérieur : loi du 20/02/1991 (baux à loyer, résidence principale).
///
/// ⚠️ Toute valeur non vérifiée est un placeholder `[À VALIDER JURISTE — …]`.
class BelgiumDocuments {
  const BelgiumDocuments._();

  // ───────────────────────────── BAIL (B.8) ────────────────────────────────
  static const CountryDocumentTemplate lease = CountryDocumentTemplate(
    countryCode: 'be',
    currencyCode: 'EUR',
    docType: 'bail',
    requiredFields: [
      RequiredField('region', 'Région (Wallonie / Bruxelles / Flandre)'),
      RequiredField('pebClasse', 'Classe du certificat PEB'),
      RequiredField('pebNumero', 'Numéro du certificat PEB'),
    ],
    sections: [
      LeaseSection(
        titre: '1. Parties',
        contenu:
            'Identité complète du bailleur et du (des) preneur(s). Bail écrit '
            'obligatoire mentionnant l\'identité des parties, la date de prise '
            'en cours, la désignation de tous les locaux et le montant du loyer.',
        source:
            '📚 art. 1erbis loi 20/02/1991 (inséré par loi 25/04/2007) ; '
            'Wallonie : décret 15/03/2018 art. 3 §1er (mentions essentielles).',
      ),
      LeaseSection(
        titre: '2. Désignation du bien',
        contenu:
            'Adresse, description et région du bien (Wallonie / Bruxelles-'
            'Capitale / Flandre) — la région détermine le régime applicable.',
        source: '📚 décrets/ordonnances régionaux 2018-2019.',
      ),
      LeaseSection(
        titre: '3. Durée et prise en cours',
        contenu:
            'Bail de référence : 9 ans. Bail de courte durée : ≤ 3 ans. Aucune '
            'durée spécifique pour le meublé (≠ France).',
        source:
            '📚 art. 3 loi 20/02/1991 ; décret wallon art. 55 ss ; Code brux. '
            'Logement art. 237 ss ; Woninghuurdecreet art. 16 ss.',
      ),
      LeaseSection(
        titre: '4. Loyer et charges',
        contenu:
            'Montant du loyer et des charges. Préciser le régime des charges : '
            'forfait OU provisions avec régularisation périodique. Bruxelles '
            '(ord. 04/04/2024) : charges = dépenses réelles sauf forfait exprès ; '
            'information précontractuelle obligatoire du type de bail précédent '
            'et du dernier loyer.',
        source:
            '📚 art. 1728ter ancien Code civil + dispositions régionales '
            '[À VALIDER JURISTE — libellé exact charges] ; Bruxelles : Code '
            'brux. Logement art. 248 (ord. 04/04/2024).',
      ),
      LeaseSection(
        titre: '5. Indexation du loyer',
        contenu:
            'Loyer indexé = loyer de base × indice santé (mois précédant '
            'l\'anniversaire de l\'entrée en vigueur) ÷ indice santé (mois '
            'précédant la signature). Une fois par an à la date anniversaire, '
            'sur demande écrite, rétroactivité limitée à 3 mois. Indexation '
            'présumée même sans clause, sauf exclusion expresse.',
        source:
            '📚 art. 1728bis ancien Code civil ✅ (indice santé, baux ≥ '
            '01/02/1994) ; art. 6 loi 20/02/1991 (présomption) ; Wallonie : '
            'décret 15/03/2018 art. 26 (dérogations PEB 2022-2023 §1erter/quater). '
            'Indices : Statbel.',
      ),
      LeaseSection(
        titre: '6. Garantie locative',
        contenu:
            'Forme et montant : compte individualisé au nom du preneur (ou '
            'e-DEPO), garantie bancaire ou autre forme admise. Plafonds : '
            'Wallonie 2 mois compte / 3 mois bancaire ; Bruxelles 2 compte / '
            '3 bancaire pour les baux < 01/11/2024, mais 2 mois MAXIMUM toutes '
            'formes pour les baux ≥ 01/11/2024 (cumul et espèces interdits) ; '
            'Flandre 3 mois max (baux ≥ 2019).',
        source:
            '📚 art. 10 loi 20/02/1991 ✅ ; Wallonie : décret 15/03/2018 art. 20 ; '
            'Bruxelles : Code brux. Logement art. 248 (ord. 04/04/2024) ; '
            'Flandre : Woninghuurdecreet art. 37.',
      ),
      LeaseSection(
        titre: '7. Performance énergétique (PEB)',
        contenu:
            'Classe énergétique et numéro du certificat PEB — référence '
            'obligatoire dans le bail et dans toute annonce.',
        source:
            '📚 Bruxelles : COBRACE/arrêtés PEB ; Wallonie : décret PEB '
            '28/11/2013 ; Flandre : Energiedecreet '
            '[À VALIDER JURISTE — articles PEB exacts par région].',
      ),
      LeaseSection(
        titre: '8. État des lieux',
        contenu:
            'État des lieux d\'entrée obligatoire, détaillé et contradictoire, '
            'à frais partagés, établi avant l\'occupation ou pendant le premier '
            'mois, et joint à l\'enregistrement du bail.',
        source:
            '📚 art. 1730 ancien Code civil (mod. loi 25/04/2007) + textes '
            'régionaux. ✅',
      ),
      LeaseSection(
        titre: '9. Entretien et réparations',
        contenu:
            'Répartition des obligations d\'entretien et des réparations entre '
            'bailleur et preneur. [À VALIDER JURISTE — répartition entretien/'
            'réparations selon la région].',
        source: '📚 dispositions régionales — à confirmer.',
      ),
      LeaseSection(
        titre: '10. Congés et résiliation',
        contenu:
            'Modalités de congé (occupation personnelle, travaux, sans motif '
            'avec indemnité) et préavis. Bruxelles : contre-préavis du locataire '
            '1 mois. [À VALIDER JURISTE — modalités de congé selon la région].',
        source:
            '📚 art. 3 loi 20/02/1991 ; Wallonie : décret 15/03/2018 art. 55 '
            '(congés du bail 9 ans) ; Bruxelles : ord. 04/04/2024 (contre-préavis '
            '1 mois) — texte des congés par région à confirmer.',
      ),
      LeaseSection(
        titre: '11. Enregistrement du bail',
        contenu:
            'Le bailleur s\'engage à faire enregistrer le bail (gratuit pour la '
            'résidence principale) dans les 2 mois, via MyRent, l\'état des '
            'lieux y étant joint. À défaut, le preneur peut quitter sans '
            'préavis ni indemnité (bail 9 ans).',
        source:
            '📚 Code des droits d\'enregistrement art. 19, 3° et 161, 12° ; '
            'obligation à charge du bailleur (loi-programme 27/12/2006) ✅ ; '
            'art. 3 §5 al. 3 loi 20/02/1991 (sanction).',
      ),
      LeaseSection(
        titre: '12. Annexe régionale',
        contenu:
            'Annexe explicative régionale obligatoire jointe au bail (page '
            'dédiée). [À VALIDER JURISTE — annexe explicative régionale (texte '
            'intégral)].',
        source:
            '📚 AR 04/05/2007 remplacé par les annexes des trois régimes '
            'régionaux.',
      ),
      LeaseSection(
        titre: 'Assurance incendie du preneur (Wallonie)',
        contenu:
            'En Wallonie, le bail contient une clause obligatoire d\'assurance '
            'incendie à charge du preneur ; le bailleur peut exiger une '
            'attestation d\'assurance à l\'entrée du locataire.',
        source: '📚 décret wallon 15/03/2018 art. 17 §2.',
      ),
      LeaseSection(
        titre: '13. Signatures',
        contenu:
            'Signature des parties. Établir un original par partie plus un '
            'exemplaire destiné à l\'enregistrement.',
        source: '📚 pratique + obligation d\'enregistrement (section 11).',
      ),
    ],
  );

  // ──────────────────── ÉTAT DES LIEUX (B.5) ───────────────────────────────
  static const CountryDocumentTemplate edl = CountryDocumentTemplate(
    countryCode: 'be',
    currencyCode: 'EUR',
    docType: 'edl',
    requiredFields: [
      RequiredField('region', 'Région'),
    ],
    sections: [
      LeaseSection(
        titre: 'Cadre',
        contenu:
            'État des lieux d\'entrée détaillé et contradictoire, à frais '
            'partagés, annexé au bail enregistré. L\'état des lieux de sortie '
            'suit le même formalisme et sert de base aux retenues sur garantie.',
        source: '📚 art. 1730 ancien Code civil (mod. loi 25/04/2007). ✅',
      ),
      LeaseSection(
        titre: 'Cartouche d\'enregistrement',
        contenu:
            'Mention « annexé au bail enregistré le … ». Retirer toute '
            'référence à la loi ALUR / au droit français.',
        source: '📚 obligation d\'enregistrement BE (bail + EDL).',
      ),
    ],
  );

  // ─────────────────────── QUITTANCE (B.6) ─────────────────────────────────
  static const CountryDocumentTemplate quittance = CountryDocumentTemplate(
    countryCode: 'be',
    currencyCode: 'EUR',
    docType: 'quittance',
    requiredFields: [],
    sections: [
      LeaseSection(
        titre: 'Quittance de loyer',
        contenu:
            'Parties, bien, période, loyer et charges ventilés (EUR), date, '
            'mode de paiement, mention « pour acquit ». Obligatoire pour tout '
            'paiement en espèces, délivrée sur demande dans les autres cas.',
        source:
            '📚 droit commun de la preuve du paiement '
            '[À VALIDER JURISTE — base légale de la quittance].',
      ),
    ],
  );

  /// Tous les documents BE, par type.
  static const Map<String, CountryDocumentTemplate> all = {
    'bail': lease,
    'edl': edl,
    'quittance': quittance,
  };
}
