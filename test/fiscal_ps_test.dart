import 'package:flutter_test/flutter_test.dart';
import 'package:adda_location/services/fiscalite_service.dart';
import 'package:adda_location/services/sci_service.dart';

/// Règle de référence (droit en vigueur) :
/// - Prélèvements sociaux sur les revenus du patrimoine : 17,2 %
///   (CSG 9,2 % + CRDS 0,5 % + prélèvement de solidarité 7,5 %) depuis 2018,
///   IDENTIQUES pour les revenus fonciers et les revenus meublés (LMNP).
/// - PFU sur dividendes (SCI à l'IS) : 30 % (12,8 % IR + 17,2 % PS).
/// Ces tests valident la règle, pas une simple recopie des constantes :
/// foncier et meublé doivent rester ÉGAUX, et le total doit se décomposer.
void main() {
  group('Prélèvements sociaux — barème par année', () {
    test('Foncier : 17,2 % pour 2018-2026', () {
      for (final year in [2018, 2024, 2025, 2026]) {
        expect(BaremeIR2026.psFoncierPour(year).total, closeTo(0.172, 1e-9));
      }
    });

    test('Meublé (LMNP) : 17,2 %, identique au foncier sur 2018-2026', () {
      for (final year in [2018, 2024, 2025, 2026]) {
        expect(BaremeIR2026.psMeublePour(year).total, closeTo(0.172, 1e-9));
        // Aucune divergence foncier/meublé ne doit exister.
        expect(BaremeIR2026.psMeublePour(year).total,
            closeTo(BaremeIR2026.psFoncierPour(year).total, 1e-9));
      }
    });

    test('Décomposition CSG/CRDS/solidarité = 9,2 / 0,5 / 7,5 (foncier=meublé)',
        () {
      for (final year in [2018, 2024, 2025, 2026]) {
        for (final ps in [
          BaremeIR2026.psFoncierPour(year),
          BaremeIR2026.psMeublePour(year),
        ]) {
          expect(ps.csg, closeTo(0.092, 1e-9));
          expect(ps.crds, closeTo(0.005, 1e-9));
          expect(ps.solidarite, closeTo(0.075, 1e-9));
          // Le total est bien la somme des composantes.
          expect(ps.total, closeTo(ps.csg + ps.crds + ps.solidarite, 1e-9));
        }
      }
    });

    test('Année hors barème lève PrelevementsSociauxIndisponibles', () {
      expect(() => BaremeIR2026.psFoncierPour(2017),
          throwsA(isA<PrelevementsSociauxIndisponibles>()));
      expect(() => BaremeIR2026.psMeublePour(2050),
          throwsA(isA<PrelevementsSociauxIndisponibles>()));
    });

    test('aPSPour : true pour 2018-2026, false sinon', () {
      expect(BaremeIR2026.aPSPour(2018), isTrue);
      expect(BaremeIR2026.aPSPour(2025), isTrue);
      expect(BaremeIR2026.aPSPour(2026), isTrue);
      expect(BaremeIR2026.aPSPour(2017), isFalse);
      expect(BaremeIR2026.aPSPour(2027), isFalse);
    });
  });

  group('Wrappers tauxPSFoncierPour / tauxPSMeublePour (compat anciens seuils)',
      () {
    test('Avant 2012 : 13,5 %', () {
      expect(BaremeIR2026.tauxPSFoncierPour(2010), closeTo(0.135, 1e-9));
      expect(BaremeIR2026.tauxPSMeublePour(2010), closeTo(0.135, 1e-9));
    });

    test('2012-2017 : 15,5 %', () {
      expect(BaremeIR2026.tauxPSFoncierPour(2015), closeTo(0.155, 1e-9));
      expect(BaremeIR2026.tauxPSMeublePour(2015), closeTo(0.155, 1e-9));
    });

    test('17,2 % pour 2018-2026, foncier ET meublé alignés', () {
      for (final year in [2018, 2020, 2022, 2024, 2025, 2026]) {
        expect(BaremeIR2026.tauxPSFoncierPour(year), closeTo(0.172, 1e-9));
        expect(BaremeIR2026.tauxPSMeublePour(year), closeTo(0.172, 1e-9));
      }
    });
  });

  group('PFU SCI à l\'IS — barème par année', () {
    test('PFU 30 % (12,8 IR + 17,2 PS) sur toutes les années', () {
      for (final year in [2023, 2024, 2025, 2026, 2027]) {
        expect(SCIService.tauxPFUPour(year), closeTo(0.30, 1e-9));
      }
    });
  });
}
