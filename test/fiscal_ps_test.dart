import 'package:flutter_test/flutter_test.dart';
import 'package:adda_location/services/fiscalite_service.dart';
import 'package:adda_location/services/sci_service.dart';

/// Taux de référence — **LFSS 2026 (loi n°2025-1403)**.
///
/// ⚠️ NE PAS réinverser ces taux sans source officielle : les dates
/// d'application DIFFÈRENT entre le meublé et le PFU.
///
/// - Revenus FONCIERS (location nue) : PS **17,2 %** (CSG 9,2 % + CRDS 0,5 %
///   + solidarité 7,5 %), **inchangé toutes années**.
/// - Revenus MEUBLÉS (LMNP, tourisme, mobilité) : PS **17,2 % jusqu'à 2024**,
///   puis **18,6 %** (CSG portée à 10,6 %) — hausse **RÉTROACTIVE** aux
///   revenus perçus dès le **1er janvier 2025**.
/// - PFU sur dividendes (SCI à l'IS) : **30 % jusqu'en 2025**, **31,4 % dès
///   2026** — **NON rétroactif** (à partir du 1er janvier 2026).
void main() {
  group('PS foncier (location nue) — 17,2 % toutes années ≥ 2018', () {
    test('17,2 % de 2018 à 2026', () {
      for (final y in [2018, 2020, 2022, 2024, 2025, 2026]) {
        expect(BaremeIR2026.psFoncierPour(y).total, closeTo(0.172, 1e-9),
            reason: 'foncier $y');
        expect(BaremeIR2026.tauxPSFoncierPour(y), closeTo(0.172, 1e-9),
            reason: 'tauxPSFoncierPour $y');
      }
    });

    test('décomposition = CSG 9,2 % + CRDS 0,5 % + solidarité 7,5 %', () {
      final ps = BaremeIR2026.psFoncierPour(2026);
      expect(ps.csg, closeTo(0.092, 1e-9));
      expect(ps.crds, closeTo(0.005, 1e-9));
      expect(ps.solidarite, closeTo(0.075, 1e-9));
    });
  });

  group('PS meublé (LMNP) — 17,2 % jusqu\'à 2024, 18,6 % dès 2025', () {
    test('17,2 % pour 2018-2024', () {
      for (final y in [2018, 2020, 2022, 2023, 2024]) {
        expect(BaremeIR2026.psMeublePour(y).total, closeTo(0.172, 1e-9),
            reason: 'meublé $y');
        expect(BaremeIR2026.tauxPSMeublePour(y), closeTo(0.172, 1e-9),
            reason: 'tauxPSMeublePour $y');
      }
    });

    test('18,6 % pour 2025 et 2026 (LFSS 2026, rétroactif aux revenus 2025)',
        () {
      for (final y in [2025, 2026]) {
        expect(BaremeIR2026.psMeublePour(y).total, closeTo(0.186, 1e-9),
            reason: 'meublé $y');
        expect(BaremeIR2026.tauxPSMeublePour(y), closeTo(0.186, 1e-9),
            reason: 'tauxPSMeublePour $y');
      }
    });

    test('décomposition 2025+ = CSG 10,6 % + CRDS 0,5 % + solidarité 7,5 %',
        () {
      final ps = BaremeIR2026.psMeublePour(2025);
      expect(ps.csg, closeTo(0.106, 1e-9));
      expect(ps.crds, closeTo(0.005, 1e-9));
      expect(ps.solidarite, closeTo(0.075, 1e-9));
    });

    test('la hausse ne concerne QUE le meublé (foncier reste 17,2 % en 2025/26)',
        () {
      expect(BaremeIR2026.psFoncierPour(2025).total, closeTo(0.172, 1e-9));
      expect(BaremeIR2026.psFoncierPour(2026).total, closeTo(0.172, 1e-9));
      // et le meublé 2024 n'est pas touché
      expect(BaremeIR2026.psMeublePour(2024).total, closeTo(0.172, 1e-9));
    });
  });

  group('PFU dividendes SCI-IS — 30 % jusqu\'en 2025, 31,4 % dès 2026', () {
    test('30 % pour 2018-2025', () {
      for (final y in [2018, 2023, 2024, 2025]) {
        expect(SCIService.tauxPFUPour(y), closeTo(0.30, 1e-9), reason: 'PFU $y');
      }
    });

    test('31,4 % dès 2026 (non rétroactif)', () {
      for (final y in [2026, 2027, 2030]) {
        expect(SCIService.tauxPFUPour(y), closeTo(0.314, 1e-9),
            reason: 'PFU $y');
      }
    });
  });

  group('Disponibilité du barème PS', () {
    test('aPSPour : true pour 2018-2026, false hors plage', () {
      expect(BaremeIR2026.aPSPour(2018), isTrue);
      expect(BaremeIR2026.aPSPour(2026), isTrue);
      expect(BaremeIR2026.aPSPour(2017), isFalse);
      expect(BaremeIR2026.aPSPour(2027), isFalse);
    });

    test('année hors table → PrelevementsSociauxIndisponibles', () {
      expect(() => BaremeIR2026.psMeublePour(2017),
          throwsA(isA<PrelevementsSociauxIndisponibles>()));
      expect(() => BaremeIR2026.psFoncierPour(2050),
          throwsA(isA<PrelevementsSociauxIndisponibles>()));
    });
  });
}
