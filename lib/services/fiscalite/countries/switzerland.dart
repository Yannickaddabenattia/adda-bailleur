import '../../../models/contrat_bail.dart' show BailType;
import '../../../models/country.dart';
import '../../../models/fiscal_settings.dart';
import '../../../models/logement.dart';
import '../country_tax_config.dart';

/// Statut de l'obligation de **formule officielle de loyer initial** par canton
/// (art. 270 al. 2 CO). `partielle` = obligation limitée à certaines communes/
/// districts → l'app doit demander la précision à l'utilisateur, jamais décider
/// en silence.
enum FormuleInitiale { obligatoire, partielle, nonRequise }

/// Implémentation **Suisse** de [CountryTaxConfig].
///
/// Sources : Code des obligations (art. 253 ss, 257e, 269 ss), OBLF, OFL
/// (taux de référence), AFC/estv.admin.ch. Cf. `FISCALITE-SUISSE-2006-2026.md`.
///
/// Particularités :
/// - **Devise CHF** (les montants du bien restent en CHF, aucune conversion).
/// - Aucun taux national unique : l'impôt est estimé au **taux marginal global
///   saisi par l'utilisateur** (fédéral + cantonal + communal).
/// - Le **droit du bail est fédéral et uniforme** (garantie 3 mois, taux de
///   référence) → contrairement à la fiscalité, pas de variante cantonale.
///
/// La série du taux de référence (OFL) est **complète et vérifiée** depuis sa
/// création le 10.09.2008 (cf. [tauxReference]). Validation finale par une
/// fiduciaire suisse (GE/VD au minimum) avant publication.
class SwitzerlandTaxConfig implements CountryTaxConfig {
  const SwitzerlandTaxConfig();

  @override
  String get countryCode => 'ch';

  @override
  String get currencyCode => 'CHF';

  // ─── Constantes (✅ stables 2006-2026) ────────────────────────────────────

  /// Forfait d'entretien déductible (IFD + défaut cantonal) :
  /// bien < 10 ans → 10 %, ≥ 10 ans → 20 % du rendement locatif brut. ✅
  /// ⚠️ Certains cantons appliquent des overrides → à paramétrer par canton.
  static double forfaitEntretienTaux({required int ageBienAnnees}) =>
      ageBienAnnees < 10 ? 0.10 : 0.20;

  /// Plafond de déduction des intérêts hypothécaires : rendement imposable de
  /// la fortune + 50 000 CHF. ✅
  static const double plafondInteretsSupplement = 50000;

  /// Hausse de loyer admissible par tranche de 0,25 pt, **palier taux < 5 %**.
  /// ✅ +3 %. Voir [hausseParQuartPoint] pour les paliers ≥ 5 %.
  static const double hausseLoyerParQuartPoint = 0.03;

  /// Hausse admissible par 0,25 pt selon le **niveau** du taux de référence
  /// (OBLF art. 13 al. 1) : +3 % si taux < 5 %, +2,5 % entre 5 et 6 %, +2 %
  /// au-delà de 6 %. Aux taux actuels (≤ 1,75 %), c'est toujours +3 %.
  static double hausseParQuartPoint(double tauxReference) {
    if (tauxReference < 0.05) return 0.03;
    if (tauxReference <= 0.06) return 0.025;
    return 0.02;
  }

  /// Baisse de loyer exigible par tranche de 0,25 pt de baisse. ✅ −2,91 %.
  static const double baisseLoyerParQuartPoint = 0.0291;

  /// Part du renchérissement IPC répercutable depuis la dernière fixation. ✅
  static const double partRencherissementIPC = 0.40;

  /// Garantie de loyer maximale : 3 mois de loyer net (art. 257e CO). ✅
  static const int garantieMaxMoisLoyerNet = 3;

  /// Année d'entrée en vigueur de la suppression de la valeur locative
  /// (votation 28.09.2025, décision du Conseil fédéral 01.04.2026). Concerne
  /// les biens **occupés par le propriétaire** ; les biens loués restent
  /// imposés et déductibles. ✅
  static const int anneeSuppressionValeurLocative = 2029;

  /// Année de validité du tableau [formuleInitiale2026].
  static const int formuleInitialeAnnee = 2026;

  /// Statut de la **formule officielle de loyer initial** par canton, **valable
  /// pour l'année [formuleInitialeAnnee]**.
  ///
  /// 📚 Source : OFL, « Aperçu pour l'année 2026 » (PDF du 03.02.2026),
  /// art. 270 al. 2 CO. ⚠️ Statut révisable chaque année (effet au 1er novembre,
  /// selon le taux de logements vacants au 1er juin) → stocker l'année + lien
  /// OFL. Les cantons absents de l'aperçu OFL 2026 = [FormuleInitiale.nonRequise].
  static const Map<ChCanton, FormuleInitiale> formuleInitiale2026 = {
    // Obligation sur TOUT le territoire cantonal :
    ChCanton.bs: FormuleInitiale.obligatoire,
    ChCanton.be: FormuleInitiale.obligatoire,
    ChCanton.fr: FormuleInitiale.obligatoire,
    ChCanton.ge: FormuleInitiale.obligatoire,
    ChCanton.lu: FormuleInitiale.obligatoire,
    ChCanton.zg: FormuleInitiale.obligatoire,
    ChCanton.zh: FormuleInitiale.obligatoire,
    // Obligation PARTIELLE → l'app demande la commune/district :
    ChCanton.ne: FormuleInitiale.partielle, // communes listées par arrêté
    ChCanton.vd: FormuleInitiale.partielle, // tous districts SAUF Aigle (17.12.2025)
    // Pas d'obligation :
    ChCanton.vs: FormuleInitiale.nonRequise,
  };

  /// Statut de la formule officielle pour [canton] ([formuleInitialeAnnee]).
  /// Les cantons hors du tableau → [FormuleInitiale.nonRequise].
  static FormuleInitiale formuleInitialePour(ChCanton canton) =>
      formuleInitiale2026[canton] ?? FormuleInitiale.nonRequise;

  /// Taux hypothécaire de référence (OFL), **date d'effet ISO → taux**.
  ///
  /// 📚 Source : OFL (bwo.admin.ch), base légale art. 12a OBLF. Série **complète
  /// et vérifiée** (10.06.2026). Avant le 10.09.2008 : taux cantonaux non
  /// standardisés → non modélisés (`null`, afficher un message si bail
  /// antérieur). Prochaine publication OFL : 01.09.2026.
  static const Map<String, double> tauxReference = {
    '2008-09-10': 0.0350, // création (remplace les taux cantonaux)
    '2009-03-02': 0.0325,
    '2009-09-01': 0.0300,
    '2010-12-01': 0.0275,
    '2012-06-02': 0.0250,
    '2013-09-03': 0.0225,
    '2014-06-02': 0.0200,
    '2015-03-02': 0.0175,
    '2017-06-01': 0.0150,
    '2020-03-02': 0.0125,
    '2023-06-02': 0.0150,
    '2023-12-02': 0.0175,
    '2025-03-04': 0.0150,
    '2025-09-02': 0.0125, // inchangé aux publications du 02.03.2026 et 02.06.2026
  };

  /// Taux de référence en vigueur à la [date] = dernier palier dont la date
  /// d'effet est ≤ [date]. `null` si antérieur au 10.09.2008 (non modélisé).
  double? tauxReferenceEnVigueur(DateTime date) {
    double? courant;
    DateTime? meilleur;
    tauxReference.forEach((iso, taux) {
      final d = DateTime.parse(iso);
      if (!d.isAfter(date) && (meilleur == null || d.isAfter(meilleur!))) {
        meilleur = d;
        courant = taux;
      }
    });
    return courant;
  }

  /// Variation de loyer admissible (en proportion, ex. 0,03 = +3 %) résultant
  /// du passage du taux de référence [ancien] → [nouveau] (OBLF) :
  /// +3 % par 0,25 pt de hausse, −2,91 % par 0,25 pt de baisse. N'inclut pas
  /// le renchérissement IPC ni les hausses de coûts (à ajouter séparément).
  double variationLoyerSelonTaux(double ancien, double nouveau) {
    final quartsDePoint = (nouveau - ancien) / 0.0025;
    // Palier de hausse déterminé par le niveau du nouveau taux (OBLF art. 13).
    return quartsDePoint >= 0
        ? quartsDePoint * hausseParQuartPoint(nouveau)
        : quartsDePoint * baisseLoyerParQuartPoint;
  }

  // ─── Fiscalité des loyers ─────────────────────────────────────────────────

  @override
  TaxEstimate? computeRentalTax({
    required Logement logement,
    required int year,
    required FiscalSettings settings,
  }) {
    final missing = <String>[];
    final lines = <TaxLine>[];

    // Rendement locatif brut annuel (loyers hors charges refacturées).
    final brut = logement.loyerHC * 12;
    lines.add(TaxLine('Rendement locatif brut annuel', brut));

    // Frais d'entretien forfaitaires (10 % / 20 % selon l'âge du bien).
    double? forfait;
    final anneeConstruction = logement.anneeConstruction;
    if (anneeConstruction == null) {
      missing.add(
          'Année de construction du bien (forfait d\'entretien 10 %/20 %)');
    } else {
      final age = year - anneeConstruction;
      final taux = forfaitEntretienTaux(ageBienAnnees: age);
      forfait = brut * taux;
      lines.add(TaxLine(
        'Frais d\'entretien forfaitaires (${_pct(taux)})',
        -forfait,
        note: age < 10 ? 'Bien < 10 ans' : 'Bien ≥ 10 ans',
      ));
    }

    // Impôt foncier cantonal/communal (déductible) si valeur fiscale + taux ‰.
    double? impotFoncier;
    final vf = logement.valeurFiscale;
    final tpm = logement.tauxImpotFoncierPourMille;
    if (vf != null && tpm != null) {
      impotFoncier = vf * tpm / 1000;
      lines.add(TaxLine(
        'Impôt foncier (${_fmt(tpm)} ‰)',
        -impotFoncier,
        note: 'Déductible du revenu locatif',
      ));
    }

    // Revenu net imposable. NB : les intérêts hypothécaires et l'entretien
    // effectif ne sont pas modélisés en v1 (pas de champ dédié) → l'estimation
    // se base sur le forfait d'entretien et l'impôt foncier saisi.
    double? net;
    if (forfait != null) {
      net = brut - forfait - (impotFoncier ?? 0);
      lines.add(TaxLine('Revenu net imposable', net));
    }

    // Impôt sur le revenu au taux marginal global estimé.
    final tm = settings.tauxMarginalCH;
    if (tm == null) {
      missing.add('Taux marginal d\'imposition global — réglages Suisse');
    }
    double? impot;
    if (net != null && tm != null) {
      impot = net * tm;
      lines.add(TaxLine('Impôt sur le revenu locatif estimé', impot));
    }

    return TaxEstimate(
      currencyCode: 'CHF',
      taxableBase: net,
      estimatedTax: missing.isEmpty ? impot : null,
      isEstimate: true,
      lines: lines,
      missingInputs: missing,
    );
  }

  // ─── Droit du bail (fédéral) ──────────────────────────────────────────────

  @override
  DepositRule depositRule({
    required Logement logement,
    required DateTime leaseDate,
    BailType? bailType,
  }) =>
      const DepositRule(
        maxMonthsRent: garantieMaxMoisLoyerNet, // 3 mois de loyer net
        blockedAccountRequired: true,
        note: 'Compte bloqué au nom du locataire, intérêts au locataire '
            '(art. 257e CO). Versement sous 30 jours, au plus tard à l\'entrée.',
      );

  @override
  RentIndexationInfo indexationInfo({required Logement logement}) =>
      const RentIndexationInfo(
        indexName: 'Taux de référence + IPC',
        description:
            'Adaptation du loyer selon la variation du taux hypothécaire de '
            'référence (OFL) : +3 % / −2,91 % par 0,25 pt, + 40 % du '
            'renchérissement IPC. Formule officielle cantonale obligatoire.',
      );

  @override
  String edlTemplateFamily({required Logement logement}) => 'ch';

  @override
  String leaseTemplateFamily({required Logement logement}) => 'ch';

  // ─── Formatage interne ────────────────────────────────────────────────────

  static String _pct(double v) => '${(v * 100).toStringAsFixed(0)} %';
  static String _fmt(double v) =>
      v.toStringAsFixed(2).replaceAll('.', ',').replaceAll(',00', '');
}
