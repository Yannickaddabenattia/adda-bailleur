import '../../../models/contrat_bail.dart' show BailType;
import '../../../models/country.dart';
import '../../../models/fiscal_settings.dart';
import '../../../models/logement.dart';
import '../country_tax_config.dart';

/// Implémentation **Belgique** de [CountryTaxConfig].
///
/// Sources : CIR 92 (art. 13, 518), loi 25/04/2007 (garantie / EDL), décrets
/// régionaux baux 2018-2019. Cf. `FISCALITE-BELGIQUE-2006-2026.md`.
///
/// ⚠️ **Règle absolue des valeurs non vérifiées** : toute donnée marquée ⚠️ dans
/// le fichier de référence est codée comme **`null`** (absente des maps). Le
/// calcul ne s'effectue jamais en silence sur une valeur douteuse : la donnée
/// manquante est remontée dans `TaxEstimate.missingInputs` pour saisie manuelle.
/// Validation finale par un expert-comptable belge avant publication.
class BelgiumTaxConfig implements CountryTaxConfig {
  const BelgiumTaxConfig();

  @override
  String get countryCode => 'be';

  @override
  String get currencyCode => 'EUR';

  // ─── Constantes structurelles (✅ stables 2006-2026) ──────────────────────

  /// Majoration de 40 % du RC indexé (location privée, art. 7 CIR 92). ✅
  static const double majorationRC = 1.40;

  /// Forfait de charges 40 % (location professionnelle/société). ✅
  static const double forfaitChargesPro = 0.40;

  /// Meublé : part mobilière par défaut du loyer (40 %), sauf ventilation. ✅
  static const double splitMobilier = 0.40;

  /// Meublé : part immobilière par défaut (60 %). ✅
  static const double splitImmobilier = 0.60;

  /// Frais forfaitaires sur la part mobilière (50 %). ✅
  static const double fraisForfaitMobilier = 0.50;

  /// Coefficient d'indexation du RC (art. 518 CIR 92), **année des revenus**.
  ///
  /// 📚 Sources : SPF Finances (fin.belgium.be, « Revenu cadastral : définition
  /// et usage ») pour 2024/2025/2026 ; BDO « Chiffres clés » (13.02.2026) pour
  /// 2016-2026. Années **2016-2026 vérifiées (✅)**.
  /// ⚠️ 2006-2015 : `null` → saisie manuelle (valeurs candidates en commentaire,
  /// à confirmer via Fisconetplus par un expert-comptable avant intégration).
  ///
  /// PIÈGE D'ANNÉES : la map est indexée par **ANNÉE DES REVENUS**. À l'IPP,
  /// exercice d'imposition = année des revenus + 1 (revenus 2025 = exercice
  /// 2026 = coef 2,2446). Au précompte immobilier, exercice = année des revenus.
  /// Beaucoup de sites confondent les deux — seules les pages SPF/BDO font foi.
  static const Map<int, double?> _coefIndexationRC = {
    2016: 1.7153, 2017: 1.7491, 2018: 1.7863, 2019: 1.8230, 2020: 1.8492,
    2021: 1.8630, 2022: 1.9084, 2023: 2.0915, 2024: 2.1763, 2025: 2.2446,
    2026: 2.3000,
    // ⚠️ 2006-2015 : null. Candidates à confirmer (Fisconetplus) :
    // 2006:1,3889 2007:1,4276 2008:1,4796 2009:1,5461 2010:1,5461
    // 2011:1,5790 2012:1,6349 2013:1,6813 2014:1,7000 2015:1,7057
    2006: null, 2007: null, 2008: null, 2009: null, 2010: null,
    2011: null, 2012: null, 2013: null, 2014: null, 2015: null,
  };

  /// Coefficient d'indexation pour l'[year] des revenus, ou `null` si non
  /// vérifié/non publié (→ saisie manuelle).
  double? coefIndexationRC(int year) => _coefIndexationRC[year];

  /// Taux de précompte mobilier applicable à la **part meublée**.
  ///
  /// 📚 Source : art. 269 CIR 92 (modifié). Série consolidée : 30 % depuis 2017
  /// ✅ ; 27 % en 2016 ✅ (généralisation du taux ordinaire aux biens mobiliers) ;
  /// 25 % de 2013 à 2015 ✅ ; 15 % de 2006 à 2011 ✅.
  /// ⚠️ 2012 : la hausse 21/25 % de 2012 visait intérêts/dividendes ; le statut
  /// de la location mobilière cette année-là reste à confirmer → `null` (saisie).
  double? tauxPrecompteMobilier(int year) {
    if (year >= 2017) return 0.30; // ✅
    if (year == 2016) return 0.27; // ✅
    if (year >= 2013) return 0.25; // ✅ 2013-2015
    if (year == 2012) return null; // ⚠️ à confirmer par l'expert
    return 0.15; // ✅ 2006-2011
  }

  /// Taux de base du précompte immobilier par région (charge du bailleur).
  /// W/B ✅ 1,25 %. Flandre ✅ **3,97 %** (Vlabel/vlaanderen.be) ; ⚠️ l'année de
  /// bascule 2,5 %→3,97 % (probable exercice 2018, réforme neutre via les
  /// centimes provinciaux) reste à confirmer mais **non bloquant** : dans l'app
  /// le précompte BE est saisi (`precompteImmobilierAnnuel`), ce taux ne sert
  /// qu'à l'estimation.
  /// Note 2026 : le tarif réduit 2,4 % (location à une woonmaatschappij) est
  /// supprimé pour les baux dès le 01/01/2026 (baux antérieurs maintenus) —
  /// hors périmètre v1.
  double? tauxBasePrecompteImmo(BeRegion region, int year) {
    switch (region) {
      case BeRegion.wallonie:
        return 0.0125; // ✅
      case BeRegion.bruxelles:
        return 0.0125; // ✅ (agglo ~2,25 % effectif avec additionnels)
      case BeRegion.flandre:
        return year >= 2018 ? 0.0397 : null; // ✅ 3,97 % ; ⚠️ année bascule
    }
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

    final estMeuble = logement.statutFiscal == StatutFiscal.lmnp ||
        logement.statutFiscal == StatutFiscal.lmp ||
        logement.statutFiscal == StatutFiscal.locCommercialEquipe;

    // ── Partie immobilière : RC indexé × 1,40 (art. 7 CIR 92) ───────────────
    // Régime « location à un particulier (privé) ». Pour le meublé, la part
    // immobilière est imposée sur la même base cadastrale (le split 60/40 ne
    // s'applique qu'à la part MOBILIÈRE, cf. §2.3).
    final rc = logement.revenuCadastral;
    final coef = coefIndexationRC(year);
    if (rc == null) {
      missing.add('Revenu cadastral (RC 1975, non indexé) du bien');
    }
    if (coef == null) {
      missing.add(
          "Coefficient d'indexation du RC pour $year (non publié/non vérifié)");
    }
    double? baseImmo;
    if (rc != null && coef != null) {
      baseImmo = rc * coef * majorationRC;
      lines.add(TaxLine(
        'Base immobilière (RC × ${_fmt(coef)} × 1,40)',
        baseImmo,
        note: 'RC indexé majoré de 40 % (art. 7 CIR 92)',
      ));
    }

    // ── Impôt des personnes physiques au taux marginal + communal ───────────
    final tm = settings.tauxMarginalBE;
    final tc = settings.tauxCommunalBE;
    if (tm == null) {
      missing.add('Taux marginal IPP (25/40/45/50 %) — réglages Belgique');
    }
    if (tc == null) {
      missing.add('Taux des centimes additionnels communaux — réglages');
    }
    double? impotImmo;
    if (baseImmo != null && tm != null && tc != null) {
      impotImmo = baseImmo * tm * (1 + tc);
      lines.add(TaxLine('IPP estimé sur la part immobilière', impotImmo));
    }

    // ── Partie mobilière (meublé uniquement) ────────────────────────────────
    // Base = loyer total × 40 % × (1 − 50 %) ; impôt = base × précompte mobilier.
    double? impotMobilier;
    if (estMeuble) {
      final loyerAnnuel = logement.loyerHC * 12;
      final tpm = tauxPrecompteMobilier(year);
      if (tpm == null) {
        missing.add(
            'Taux de précompte mobilier pour $year (< 2017, non vérifié)');
      } else {
        final baseMob =
            loyerAnnuel * splitMobilier * (1 - fraisForfaitMobilier);
        impotMobilier = baseMob * tpm;
        lines.add(TaxLine(
          'Précompte mobilier (part meublée 40 % − 50 % frais)',
          impotMobilier,
          note: 'Loyer annuel × 40 % × 50 % × ${_pct(tpm)}',
        ));
      }
    }

    // ── Précompte immobilier (charge annuelle du bailleur, informatif) ───────
    if (logement.precompteImmobilierAnnuel != null) {
      lines.add(TaxLine(
        'Précompte immobilier annuel',
        logement.precompteImmobilierAnnuel,
        note: 'Charge du propriétaire — non déductible en régime privé',
      ));
    }

    final hasTax = impotImmo != null || impotMobilier != null;
    final tax = hasTax ? (impotImmo ?? 0) + (impotMobilier ?? 0) : null;

    return TaxEstimate(
      currencyCode: 'EUR',
      taxableBase: baseImmo,
      estimatedTax: missing.isEmpty ? tax : null,
      isEstimate: true,
      lines: lines,
      missingInputs: missing,
    );
  }

  // ─── Droit du bail ────────────────────────────────────────────────────────

  @override
  DepositRule depositRule({
    required Logement logement,
    required DateTime leaseDate,
    BailType? bailType,
  }) {
    // Garantie locative — compte bloqué au nom du locataire (loi 25/04/2007)
    // ou e-DEPO.
    //  • Wallonie : 2 mois compte / 3 mois bancaire ✅ (décret 15/03/2018 art. 20).
    //  • Bruxelles : baux < 01/11/2024 → 2 compte / 3 bancaire ; baux ≥
    //    01/11/2024 → MAX 2 mois TOUTES FORMES ✅ (Code brux. Logement art. 248,
    //    ord. 04/04/2024 ; cumul interdit ; versement en espèces interdit ;
    //    libération sous 2 mois, pénalité 10 %/mois de retard).
    //  • Flandre : 3 mois max ✅ (Woninghuurdecreet art. 37, baux dès 01/01/2019 ;
    //    cumul interdit, Vred. Gent 08/09/2020). Avant : 2 mois (fédéral).
    final region = logement.beRegion;
    var note = 'Compte bloqué au nom du locataire (ou e-DEPO, SPF Finances).';
    int mois;
    switch (region) {
      case BeRegion.flandre:
        final apres2019 = !leaseDate.isBefore(DateTime(2019, 1, 1));
        mois = apres2019 ? 3 : 2;
        if (apres2019) {
          note += ' Flandre : 3 mois max (Woninghuurdecreet art. 37) ; '
              'cumul de deux formes interdit.';
        }
        break;
      case BeRegion.bruxelles:
        final apresReforme = !leaseDate.isBefore(DateTime(2024, 11, 1));
        mois = apresReforme ? 2 : 3; // ≥01/11/2024 : 2 (toutes formes) ; avant : 3 (bancaire)
        note += apresReforme
            ? ' Bruxelles (bail ≥ 01/11/2024) : 2 mois max toutes formes '
                '(art. 248, ord. 04/04/2024) ; cumul et espèces interdits.'
            : ' Bruxelles (bail < 01/11/2024) : 2 mois compte / 3 mois bancaire.';
        break;
      case BeRegion.wallonie:
      case null:
        mois = 2; // ✅ Wallonie : décret 15/03/2018 art. 20 (compte) ; fédéral 2007
    }
    return DepositRule(
      maxMonthsRent: mois,
      blockedAccountRequired: true,
      note: note,
    );
  }

  @override
  RentIndexationInfo indexationInfo({required Logement logement}) =>
      const RentIndexationInfo(
        indexName: 'Indice santé',
        description:
            'Indexation annuelle à la date anniversaire selon l\'indice santé '
            '(Statbel), 1×/an max, non rétroactive (max 3 mois d\'arriérés). '
            'Gel partiel possible 2022-2023 selon le PEB et la région.',
      );

  @override
  String edlTemplateFamily({required Logement logement}) => 'be';

  @override
  String leaseTemplateFamily({required Logement logement}) => 'be';

  // ─── Formatage interne ────────────────────────────────────────────────────

  static String _fmt(double v) => v.toStringAsFixed(4).replaceAll('.', ',');
  static String _pct(double v) =>
      '${(v * 100).toStringAsFixed(0)} %';
}
