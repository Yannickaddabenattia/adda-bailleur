import 'package:flutter_test/flutter_test.dart';
import 'package:adda_location/services/fiscalite_service.dart';
import 'package:adda_location/services/sci_service.dart';

void main() {
  group('Prélèvements sociaux — barème par année', () {
    test('Foncier : 17,2 % maintenu pour 2024, 2025 et 2026', () {
      expect(BaremeIR2026.psFoncierPour(2024).total, closeTo(0.172, 1e-9));
      expect(BaremeIR2026.psFoncierPour(2025).total, closeTo(0.172, 1e-9));
      expect(BaremeIR2026.psFoncierPour(2026).total, closeTo(0.172, 1e-9));
    });

    test('Meublé : 17,2 % en 2024, 18,6 % dès 2025 (LFSS 2026 rétroactif)', () {
      expect(BaremeIR2026.psMeublePour(2024).total, closeTo(0.172, 1e-9));
      expect(BaremeIR2026.psMeublePour(2025).total, closeTo(0.186, 1e-9));
      expect(BaremeIR2026.psMeublePour(2026).total, closeTo(0.186, 1e-9));
    });

    test('Composante CSG : 9,2 % foncier, 10,6 % meublé en 2025+', () {
      expect(BaremeIR2026.psFoncierPour(2025).csg, closeTo(0.092, 1e-9));
      expect(BaremeIR2026.psMeublePour(2025).csg, closeTo(0.106, 1e-9));
      expect(BaremeIR2026.psFoncierPour(2026).csg, closeTo(0.092, 1e-9));
      expect(BaremeIR2026.psMeublePour(2026).csg, closeTo(0.106, 1e-9));
    });

    test('CRDS et solidarité inchangés sur toutes les années 2018-2026', () {
      for (final year in [2018, 2020, 2024, 2025, 2026]) {
        expect(BaremeIR2026.psFoncierPour(year).crds, closeTo(0.005, 1e-9));
        expect(BaremeIR2026.psFoncierPour(year).solidarite, closeTo(0.075, 1e-9));
        expect(BaremeIR2026.psMeublePour(year).crds, closeTo(0.005, 1e-9));
        expect(BaremeIR2026.psMeublePour(year).solidarite, closeTo(0.075, 1e-9));
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

  group('Wrappers tauxPSFoncierPour / tauxPSMeublePour (compat anciens seuils)', () {
    test('Avant 2012 : 13,5 %', () {
      expect(BaremeIR2026.tauxPSFoncierPour(2010), closeTo(0.135, 1e-9));
      expect(BaremeIR2026.tauxPSMeublePour(2010), closeTo(0.135, 1e-9));
    });

    test('2012-2017 : 15,5 %', () {
      expect(BaremeIR2026.tauxPSFoncierPour(2015), closeTo(0.155, 1e-9));
      expect(BaremeIR2026.tauxPSMeublePour(2015), closeTo(0.155, 1e-9));
    });

    test('Convergence à 17,2 % pour 2018-2024 (foncier ET meublé)', () {
      for (final year in [2018, 2020, 2022, 2024]) {
        expect(BaremeIR2026.tauxPSFoncierPour(year), closeTo(0.172, 1e-9));
        expect(BaremeIR2026.tauxPSMeublePour(year), closeTo(0.172, 1e-9));
      }
    });

    test('Divergence foncier (17,2 %) vs meublé (18,6 %) à partir de 2025', () {
      expect(BaremeIR2026.tauxPSFoncierPour(2025), closeTo(0.172, 1e-9));
      expect(BaremeIR2026.tauxPSMeublePour(2025), closeTo(0.186, 1e-9));
      expect(BaremeIR2026.tauxPSFoncierPour(2026), closeTo(0.172, 1e-9));
      expect(BaremeIR2026.tauxPSMeublePour(2026), closeTo(0.186, 1e-9));
    });
  });

  group('PFU SCI à l\'IS — barème par année', () {
    test('Jusqu\'en 2025 : PFU 30 % (12,8 IR + 17,2 PS)', () {
      expect(SCIService.tauxPFUPour(2023), closeTo(0.30, 1e-9));
      expect(SCIService.tauxPFUPour(2024), closeTo(0.30, 1e-9));
      expect(SCIService.tauxPFUPour(2025), closeTo(0.30, 1e-9));
    });

    test('Dès 2026 : PFU 31,4 % (12,8 IR + 18,6 PS, LFSS 2026)', () {
      expect(SCIService.tauxPFUPour(2026), closeTo(0.314, 1e-9));
      expect(SCIService.tauxPFUPour(2027), closeTo(0.314, 1e-9));
    });
  });
}
