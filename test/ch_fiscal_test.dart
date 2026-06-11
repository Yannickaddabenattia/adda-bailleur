import 'package:flutter_test/flutter_test.dart';

import 'package:adda_location/models/country.dart';
import 'package:adda_location/models/fiscal_settings.dart';
import 'package:adda_location/models/logement.dart';
import 'package:adda_location/services/fiscalite/countries/switzerland.dart';

/// Fiscalité immobilière SUISSE — vérifie la logique de [SwitzerlandTaxConfig].
///
/// Références légales (citées pour empêcher une future « correction » inversée) :
///   - Forfait d'entretien 10 % (< 10 ans) / 20 % (≥ 10 ans) : pratique IFD +
///     majorité des cantons.
///   - Plafond intérêts hypothécaires : rendement fortune + 50 000 CHF.
///   - Garantie de loyer max 3 mois, compte bloqué : art. 257e CO.
///   - Adaptation du loyer selon le taux de référence (OFL) : +3 % / −2,91 %
///     par 0,25 pt — OBLF (ordonnance sur le bail).
///
/// ⚠️ Les paliers du taux de référence 2009-2019 (non vérifiés) sont absents :
/// la recherche ne renvoie jamais une valeur inventée.
void main() {
  const ch = SwitzerlandTaxConfig();

  Logement bien({
    double loyerHC = 2000,
    int? anneeConstruction,
    double? valeurFiscale,
    double? tauxImpotFoncierPourMille,
  }) {
    final l = Logement.create(
      libelle: 'Test CH',
      adresse: 'Rue Y',
      codePostal: '1200',
      ville: 'Genève',
      type: LogementType.appartement,
      surface: 80,
      nbPieces: 3,
      loyerHC: loyerHC,
      charges: 0,
      country: Country.suisse,
      chCanton: ChCanton.ge,
      currencyCode: 'CHF',
      valeurFiscale: valeurFiscale,
      tauxImpotFoncierPourMille: tauxImpotFoncierPourMille,
    );
    // anneeConstruction est un champ diagnostic (non exposé par create()).
    l.anneeConstruction = anneeConstruction;
    return l;
  }

  group('Forfait d\'entretien (IFD)', () {
    test('10 % si < 10 ans, 20 % si ≥ 10 ans', () {
      expect(SwitzerlandTaxConfig.forfaitEntretienTaux(ageBienAnnees: 5), 0.10);
      expect(SwitzerlandTaxConfig.forfaitEntretienTaux(ageBienAnnees: 9), 0.10);
      expect(SwitzerlandTaxConfig.forfaitEntretienTaux(ageBienAnnees: 10), 0.20);
      expect(SwitzerlandTaxConfig.forfaitEntretienTaux(ageBienAnnees: 30), 0.20);
    });
    test('plafond intérêts = 50 000 CHF', () {
      expect(SwitzerlandTaxConfig.plafondInteretsSupplement, 50000);
    });
  });

  group('Droit à la hausse/baisse du loyer (OBLF)', () {
    test('+0,25 pt → +3 % ; −0,25 pt → −2,91 %', () {
      expect(ch.variationLoyerSelonTaux(0.0150, 0.0175), closeTo(0.03, 1e-9));
      expect(ch.variationLoyerSelonTaux(0.0175, 0.0150), closeTo(-0.0291, 1e-9));
    });
    test('+0,50 pt → +6 % ; taux inchangé → 0 %', () {
      expect(ch.variationLoyerSelonTaux(0.0125, 0.0175), closeTo(0.06, 1e-9));
      expect(ch.variationLoyerSelonTaux(0.0150, 0.0150), 0);
    });
    test('part du renchérissement IPC répercutable = 40 %', () {
      expect(SwitzerlandTaxConfig.partRencherissementIPC, 0.40);
    });
  });

  group('Taux de référence en vigueur (OFL, art. 12a OBLF — série complète)', () {
    test('la série contient 14 paliers vérifiés', () {
      expect(SwitzerlandTaxConfig.tauxReference.length, 14);
    });
    test('valeurs historiques officielles', () {
      expect(ch.tauxReferenceEnVigueur(DateTime(2008, 10, 1)), 0.0350);
      expect(ch.tauxReferenceEnVigueur(DateTime(2021, 6, 1)), 0.0125);
      expect(ch.tauxReferenceEnVigueur(DateTime(2024, 6, 1)), 0.0175);
      expect(ch.tauxReferenceEnVigueur(DateTime(2026, 6, 10)), 0.0125); // actuel
    });
    test('dernier palier ≤ date (cas intermédiaires)', () {
      expect(ch.tauxReferenceEnVigueur(DateTime(2024, 1, 1)), 0.0175);
      expect(ch.tauxReferenceEnVigueur(DateTime(2025, 4, 1)), 0.0150);
      expect(ch.tauxReferenceEnVigueur(DateTime(2025, 10, 1)), 0.0125);
    });
    test('antérieur au 10.09.2008 → null (taux cantonaux non modélisés)', () {
      expect(ch.tauxReferenceEnVigueur(DateTime(2007, 1, 1)), isNull);
      expect(ch.tauxReferenceEnVigueur(DateTime(2008, 9, 9)), isNull);
    });
  });

  group('Formule officielle loyer initial 2026 (OFL, art. 270 al. 2 CO)', () {
    test('obligatoire / partielle / non requise selon canton', () {
      expect(SwitzerlandTaxConfig.formuleInitiale2026[ChCanton.zh],
          FormuleInitiale.obligatoire);
      expect(SwitzerlandTaxConfig.formuleInitiale2026[ChCanton.vs],
          FormuleInitiale.nonRequise);
      expect(SwitzerlandTaxConfig.formuleInitiale2026[ChCanton.vd],
          FormuleInitiale.partielle); // l'app pose la question du district
    });
    test('canton absent de l\'aperçu OFL → non requise par défaut', () {
      expect(SwitzerlandTaxConfig.formuleInitialePour(ChCanton.ti),
          FormuleInitiale.nonRequise);
    });
  });

  group('computeRentalTax — revenu net au taux marginal', () {
    test('calcul complet (brut − forfait − impôt foncier) × taux marginal', () {
      final r = ch.computeRentalTax(
        logement: bien(
          loyerHC: 2000,
          anneeConstruction: 2000,
          valeurFiscale: 500000,
          tauxImpotFoncierPourMille: 1.0,
        ),
        year: 2025, // âge 25 → forfait 20 %
        settings: FiscalSettings(tauxMarginalCH: 0.30),
      )!;
      // brut = 24000 ; forfait 20 % = 4800 ; foncier = 500000 × 1‰ = 500
      // net = 24000 − 4800 − 500 = 18700 ; impôt = 18700 × 0,30 = 5610
      expect(r.taxableBase, closeTo(18700, 0.01));
      expect(r.estimatedTax, closeTo(5610, 0.01));
      expect(r.currencyCode, 'CHF');
      expect(r.isEstimate, isTrue);
      expect(r.missingInputs, isEmpty);
    });

    test('taux marginal non saisi → estimatedTax null + missingInputs', () {
      final r = ch.computeRentalTax(
        logement: bien(loyerHC: 2000, anneeConstruction: 2000),
        year: 2025,
        settings: FiscalSettings(), // tauxMarginalCH null
      )!;
      expect(r.estimatedTax, isNull);
      expect(r.missingInputs, isNotEmpty);
    });

    test('année de construction manquante → missingInputs (forfait inconnu)', () {
      final r = ch.computeRentalTax(
        logement: bien(loyerHC: 2000, anneeConstruction: null),
        year: 2025,
        settings: FiscalSettings(tauxMarginalCH: 0.30),
      )!;
      expect(r.estimatedTax, isNull);
      expect(
        r.missingInputs.any((m) => m.toLowerCase().contains('construction')),
        isTrue,
      );
    });
  });

  group('Garantie de loyer (art. 257e CO)', () {
    test('3 mois max, compte bloqué', () {
      final d = ch.depositRule(
        logement: bien(),
        leaseDate: DateTime(2025, 1, 1),
      );
      expect(d.maxMonthsRent, 3);
      expect(d.blockedAccountRequired, isTrue);
    });
  });

  test('réforme valeur locative : entrée en vigueur 2029', () {
    expect(SwitzerlandTaxConfig.anneeSuppressionValeurLocative, 2029);
  });
}
