import 'package:flutter_test/flutter_test.dart';

import 'package:adda_location/core/legal/france_bail_rules.dart';

/// A5 — encadrement des loyers (zones tendues) : le loyer hors charges ne peut
/// excéder le loyer de référence majoré (€/m² × surface), sauf complément de
/// loyer justifié. Avertissement NON bloquant.
/// 📚 loi n° 89-462, art. 140 ; art. 17 & 25-9.
void main() {
  test('hors zone d\'encadrement → aucun avertissement', () {
    expect(
      FranceBailRules.encadrementDepassementWarning(
        zoneEncadrement: false,
        loyerHC: 5000,
        surfaceM2: 30,
        loyerReferenceMajore: 25,
      ),
      isNull,
    );
  });

  test('loyer ≤ réf. majoré × surface → aucun avertissement', () {
    // 30 m² × 29,16 = 874,80 € ; loyer 850 € → conforme.
    expect(
      FranceBailRules.encadrementDepassementWarning(
        zoneEncadrement: true,
        loyerHC: 850,
        surfaceM2: 30,
        loyerReferenceMajore: 29.16,
      ),
      isNull,
    );
  });

  test('loyer > réf. majoré × surface (sans complément) → avertissement', () {
    expect(
      FranceBailRules.encadrementDepassementWarning(
        zoneEncadrement: true,
        loyerHC: 1000,
        surfaceM2: 30,
        loyerReferenceMajore: 29.16,
      ),
      allOf(isNotNull, contains('art. 140')),
    );
  });

  test('dépassement couvert par un complément de loyer → aucun avertissement',
      () {
    // Plafond 874,80 € + complément 150 € = 1024,80 € ; loyer 1000 € → OK.
    expect(
      FranceBailRules.encadrementDepassementWarning(
        zoneEncadrement: true,
        loyerHC: 1000,
        surfaceM2: 30,
        loyerReferenceMajore: 29.16,
        complementLoyer: 150,
      ),
      isNull,
    );
  });

  test('réf. majoré absent ou nul → pas d\'avertissement (donnée à saisir)', () {
    expect(
      FranceBailRules.encadrementDepassementWarning(
        zoneEncadrement: true,
        loyerHC: 1000,
        surfaceM2: 30,
        loyerReferenceMajore: null,
      ),
      isNull,
    );
  });
}
