import 'package:flutter_test/flutter_test.dart';

import 'package:adda_location/models/country.dart';
import 'package:adda_location/services/fiscalite/countries/switzerland.dart';
import 'package:adda_location/services/fiscalite/country_validations.dart';

/// Règles d'indexation par pays (D + B.4 + C.3).
///
/// 📚 Sources : France — IRL (art. 17-1 loi 89-462) ; Belgique — art. 1728bis
/// ancien Code civil (indice santé) ; Suisse — OBLF art. 13 (paliers de hausse)
/// & art. 16 (40 % IPC), CO art. 269b (indexé ≥ 5 ans) / 269c (échelonné ≥ 3 ans).
void main() {
  group('Mode d\'indexation réservé au bon pays', () {
    test('IRL réservé à la France', () {
      expect(
        CountryValidations.indexationModeError(
            country: Country.france, mode: IndexationMode.irl),
        isNull,
      );
      expect(
        CountryValidations.indexationModeError(
            country: Country.belgique, mode: IndexationMode.irl),
        isNotNull,
      );
      expect(
        CountryValidations.indexationModeError(
            country: Country.suisse, mode: IndexationMode.irl),
        isNotNull,
      );
    });

    test('Indice santé réservé à la Belgique', () {
      expect(
        CountryValidations.indexationModeError(
            country: Country.belgique, mode: IndexationMode.indiceSante),
        isNull,
      );
      expect(
        CountryValidations.indexationModeError(
            country: Country.france, mode: IndexationMode.indiceSante),
        isNotNull,
      );
    });
  });

  group('Belgique — indexation indice santé (art. 1728bis)', () {
    test('indices manquants → erreur', () {
      expect(
        CountryValidations.belgiumIndexationError(indiceSanteBase: null),
        isNotNull,
      );
    });
    test('indices fournis → ok', () {
      expect(
        CountryValidations.belgiumIndexationError(
            indiceSanteBase: 128.5, indiceSanteNouveau: 131.2),
        isNull,
      );
    });
  });

  group('Suisse — adaptation au taux de référence (OBLF)', () {
    const ch = SwitzerlandTaxConfig();

    test('+3 % / −2,91 % par 0,25 pt sous 5 % (OBLF art. 13)', () {
      expect(ch.variationLoyerSelonTaux(0.0150, 0.0175), closeTo(0.03, 1e-9));
      expect(ch.variationLoyerSelonTaux(0.0175, 0.0150), closeTo(-0.0291, 1e-9));
    });

    test('paliers de hausse selon le niveau du taux (OBLF art. 13 al. 1)', () {
      expect(SwitzerlandTaxConfig.hausseParQuartPoint(0.04), 0.03); // < 5 %
      expect(SwitzerlandTaxConfig.hausseParQuartPoint(0.055), 0.025); // 5-6 %
      expect(SwitzerlandTaxConfig.hausseParQuartPoint(0.07), 0.02); // > 6 %
    });

    test('40 % du renchérissement IPC répercutable (OBLF art. 16)', () {
      expect(SwitzerlandTaxConfig.partRencherissementIPC, 0.40);
    });
  });

  group('Suisse — durées minimales (CO)', () {
    test('bail indexé refusé si < 5 ans (art. 269b CO)', () {
      expect(CountryValidations.swissIndexedLeaseError(dureeAnnees: 4),
          isNotNull);
      expect(
          CountryValidations.swissIndexedLeaseError(dureeAnnees: 5), isNull);
    });
    test('bail échelonné refusé si < 3 ans (art. 269c CO)', () {
      expect(CountryValidations.swissStaggeredLeaseError(dureeAnnees: 2),
          isNotNull);
      expect(
          CountryValidations.swissStaggeredLeaseError(dureeAnnees: 3), isNull);
    });
  });
}
