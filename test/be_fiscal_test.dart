import 'package:flutter_test/flutter_test.dart';

import 'package:adda_location/models/country.dart';
import 'package:adda_location/models/fiscal_settings.dart';
import 'package:adda_location/models/logement.dart';
import 'package:adda_location/services/fiscalite/countries/belgium.dart';

/// Fiscalité immobilière BELGIQUE — vérifie la logique de [BelgiumTaxConfig].
///
/// Références légales (citées pour empêcher une future « correction » inversée,
/// cf. leçon LFSS 2026) :
///   - RC indexé majoré de 40 % (location privée) : art. 7 & 518 CIR 92.
///   - Coefficient d'indexation du RC : art. 518 CIR 92 (arrêté royal annuel).
///   - Meublé : split 60 % immobilier / 40 % mobilier, 50 % de frais forfait.
///   - Précompte mobilier 30 % depuis 2017 (loi du 26/12/2015, tax shift).
///   - Garantie locative : loi 25/04/2007 + décrets régionaux 2018-2019.
///
/// ⚠️ RÈGLE : les valeurs non vérifiées sont `null` (absentes des maps) → le
/// calcul ne se fait jamais en silence ; la donnée manquante est remontée.
void main() {
  const be = BelgiumTaxConfig();

  Logement bien({
    required StatutFiscal statut,
    BeRegion region = BeRegion.wallonie,
    double loyerHC = 1000,
    double? revenuCadastral,
  }) =>
      Logement.create(
        libelle: 'Test BE',
        adresse: 'Rue X',
        codePostal: '1000',
        ville: 'Bruxelles',
        type: LogementType.appartement,
        surface: 60,
        nbPieces: 2,
        loyerHC: loyerHC,
        charges: 0,
        statutFiscal: statut,
        country: Country.belgique,
        beRegion: region,
        revenuCadastral: revenuCadastral,
      );

  group('Constantes structurelles (✅ stables)', () {
    test('majoration RC = 1,40 ; split meublé 60/40 ; frais 50 %', () {
      expect(BelgiumTaxConfig.majorationRC, 1.40);
      expect(BelgiumTaxConfig.splitImmobilier, 0.60);
      expect(BelgiumTaxConfig.splitMobilier, 0.40);
      expect(BelgiumTaxConfig.fraisForfaitMobilier, 0.50);
    });
  });

  group('Coefficient d\'indexation RC (art. 518 CIR 92)', () {
    test('années vérifiées 2016-2026 (SPF Finances / BDO 13.02.2026)', () {
      expect(be.coefIndexationRC(2016), 1.7153);
      expect(be.coefIndexationRC(2017), 1.7491);
      expect(be.coefIndexationRC(2018), 1.7863);
      expect(be.coefIndexationRC(2019), 1.8230);
      expect(be.coefIndexationRC(2020), 1.8492);
      expect(be.coefIndexationRC(2021), 1.8630);
      expect(be.coefIndexationRC(2022), 1.9084);
      expect(be.coefIndexationRC(2023), 2.0915);
      expect(be.coefIndexationRC(2024), 2.1763);
      expect(be.coefIndexationRC(2025), 2.2446);
      expect(be.coefIndexationRC(2026), 2.3000);
    });
    test('2006-2015 → null (saisie manuelle, jamais inventées)', () {
      expect(be.coefIndexationRC(2006), isNull);
      expect(be.coefIndexationRC(2010), isNull);
      expect(be.coefIndexationRC(2015), isNull);
      expect(be.coefIndexationRC(2030), isNull); // hors table
    });
  });

  group('Précompte mobilier (part meublée) — art. 269 CIR 92', () {
    test('série consolidée 30 / 27 / 25 / 15 %', () {
      expect(be.tauxPrecompteMobilier(2017), 0.30); // ✅ depuis 2017
      expect(be.tauxPrecompteMobilier(2026), 0.30);
      expect(be.tauxPrecompteMobilier(2016), 0.27); // ✅
      expect(be.tauxPrecompteMobilier(2014), 0.25); // ✅ 2013-2015
      expect(be.tauxPrecompteMobilier(2013), 0.25);
      expect(be.tauxPrecompteMobilier(2008), 0.15); // ✅ 2006-2011
    });
    test('2012 ⚠️ → null (statut location mobilière à confirmer)', () {
      expect(be.tauxPrecompteMobilier(2012), isNull);
    });
  });

  group('Précompte immobilier — taux de base régional', () {
    test('Wallonie / Bruxelles = 1,25 % (✅)', () {
      expect(be.tauxBasePrecompteImmo(BeRegion.wallonie, 2025), 0.0125);
      expect(be.tauxBasePrecompteImmo(BeRegion.bruxelles, 2025), 0.0125);
    });
    test('Flandre 3,97 % dès 2018 (⚠️ bascule), null avant', () {
      expect(be.tauxBasePrecompteImmo(BeRegion.flandre, 2025), 0.0397);
      expect(be.tauxBasePrecompteImmo(BeRegion.flandre, 2017), isNull);
    });
  });

  group('computeRentalTax — location privée (RC × coef × 1,40)', () {
    test('calcul complet quand toutes les données sont présentes', () {
      final r = be.computeRentalTax(
        logement: bien(statut: StatutFiscal.locationNue, revenuCadastral: 1000),
        year: 2025,
        settings: FiscalSettings(tauxMarginalBE: 0.45, tauxCommunalBE: 0.07),
      )!;
      // base = 1000 × 2,2446 × 1,40 = 3142,44
      expect(r.taxableBase, closeTo(3142.44, 0.01));
      // IPP = base × 0,45 × (1 + 0,07) = 1513,08
      expect(r.estimatedTax, closeTo(1513.085, 0.01));
      expect(r.currencyCode, 'EUR');
      expect(r.isEstimate, isTrue);
      expect(r.missingInputs, isEmpty);
    });

    test('RC manquant → estimatedTax null + missingInputs (pas de calcul)', () {
      final r = be.computeRentalTax(
        logement: bien(statut: StatutFiscal.locationNue, revenuCadastral: null),
        year: 2025,
        settings: FiscalSettings(tauxMarginalBE: 0.45, tauxCommunalBE: 0.07),
      )!;
      expect(r.estimatedTax, isNull);
      expect(r.missingInputs, isNotEmpty);
      expect(r.isComplete, isFalse);
    });

    test('coefficient non vérifié (revenus 2010) → missingInputs', () {
      final r = be.computeRentalTax(
        logement: bien(statut: StatutFiscal.locationNue, revenuCadastral: 1000),
        year: 2010,
        settings: FiscalSettings(tauxMarginalBE: 0.45, tauxCommunalBE: 0.07),
      )!;
      expect(r.estimatedTax, isNull);
      expect(r.missingInputs.any((m) => m.contains('2010')), isTrue);
    });

    test('exemple officiel SPF : RC 450 € → base revenus 2025 puis 2026', () {
      final r2025 = be.computeRentalTax(
        logement: bien(statut: StatutFiscal.locationNue, revenuCadastral: 450),
        year: 2025,
        settings: FiscalSettings(tauxMarginalBE: 0.45, tauxCommunalBE: 0.07),
      )!;
      // 450 × 2,2446 × 1,40 = 1414,098
      expect(r2025.taxableBase, closeTo(1414.098, 0.01));
      final r2026 = be.computeRentalTax(
        logement: bien(statut: StatutFiscal.locationNue, revenuCadastral: 450),
        year: 2026,
        settings: FiscalSettings(tauxMarginalBE: 0.45, tauxCommunalBE: 0.07),
      )!;
      // 450 × 2,3 × 1,40 = 1449
      expect(r2026.taxableBase, closeTo(1449.0, 0.01));
    });

    test('taux utilisateur non saisis → missingInputs', () {
      final r = be.computeRentalTax(
        logement: bien(statut: StatutFiscal.locationNue, revenuCadastral: 1000),
        year: 2025,
        settings: FiscalSettings(), // tauxMarginalBE/tauxCommunalBE null
      )!;
      expect(r.estimatedTax, isNull);
      expect(r.missingInputs.length, greaterThanOrEqualTo(2));
    });
  });

  group('computeRentalTax — meublé (part mobilière ajoutée)', () {
    test('split 40 % × 50 % × 30 % sur le loyer annuel', () {
      final r = be.computeRentalTax(
        logement: bien(
          statut: StatutFiscal.lmnp,
          loyerHC: 1000,
          revenuCadastral: 1000,
        ),
        year: 2025,
        settings: FiscalSettings(tauxMarginalBE: 0.45, tauxCommunalBE: 0.07),
      )!;
      // mobilier = 12000 × 0,40 × 0,50 × 0,30 = 720
      // immobilier = 1513,085 ; total = 2233,085
      expect(r.estimatedTax, closeTo(2233.085, 0.01));
    });
  });

  group('Garantie locative (loi 25/04/2007 + décrets régionaux)', () {
    test('Wallonie / Bruxelles : 2 mois, compte bloqué', () {
      final w = be.depositRule(
        logement: bien(statut: StatutFiscal.locationNue),
        leaseDate: DateTime(2022, 6, 1),
      );
      expect(w.maxMonthsRent, 2);
      expect(w.blockedAccountRequired, isTrue);
    });
    test('Flandre : 3 mois pour baux dès 2019, 2 mois avant', () {
      final apres = be.depositRule(
        logement: bien(statut: StatutFiscal.locationNue, region: BeRegion.flandre),
        leaseDate: DateTime(2020, 1, 1),
      );
      final avant = be.depositRule(
        logement: bien(statut: StatutFiscal.locationNue, region: BeRegion.flandre),
        leaseDate: DateTime(2018, 6, 1),
      );
      expect(apres.maxMonthsRent, 3);
      expect(avant.maxMonthsRent, 2);
    });
  });

  test('indexation = indice santé', () {
    final info = be.indexationInfo(logement: bien(statut: StatutFiscal.locationNue));
    expect(info.indexName, 'Indice santé');
  });
}
