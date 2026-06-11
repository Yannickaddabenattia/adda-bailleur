import 'package:flutter_test/flutter_test.dart';

import 'package:adda_location/models/contrat_bail.dart' show BailType;
import 'package:adda_location/models/country.dart';
import 'package:adda_location/services/fiscalite/country_validations.dart';

/// Validation du dépôt de garantie par pays (D).
///
/// 📚 Sources : France — loi n°89-462 art. 22 / ELAN (1 nu / 2 meublé / 0
/// mobilité) ; Belgique — décret wallon 15/03/2018, Code bruxellois du
/// Logement, Vlaams Woninghuurdecreet art. 37 (W/B 2 mois, FL 3 mois max dès
/// 01/01/2019, ✅) ; Suisse — art. 257e CO (3 mois de loyer net).
void main() {
  String? dep({
    required Country country,
    BeRegion? region,
    BailType? bailType,
    DateTime? leaseDate,
    required double mois,
  }) =>
      CountryValidations.depositError(
        country: country,
        region: region,
        bailType: bailType,
        leaseDate: leaseDate,
        moisDepot: mois,
      );

  test('2 mois acceptés en Wallonie (plafond 2)', () {
    expect(dep(country: Country.belgique, region: BeRegion.wallonie, mois: 2),
        isNull);
  });

  test('2 mois refusés en France (location nue, plafond 1)', () {
    final err = dep(country: Country.france, bailType: BailType.vide, mois: 2);
    expect(err, isNotNull);
    expect(err, contains('89-462'));
  });

  test('3 mois acceptés en Flandre pour un bail dès 2019', () {
    expect(
      dep(
        country: Country.belgique,
        region: BeRegion.flandre,
        leaseDate: DateTime(2020, 1, 1),
        mois: 3,
      ),
      isNull,
    );
  });

  test('3 mois acceptés en Suisse (art. 257e CO)', () {
    expect(dep(country: Country.suisse, mois: 3), isNull);
  });

  test('3,5 mois refusés partout', () {
    expect(dep(country: Country.france, bailType: BailType.vide, mois: 3.5),
        isNotNull);
    expect(dep(country: Country.belgique, region: BeRegion.flandre, leaseDate: DateTime(2020), mois: 3.5),
        isNotNull);
    final chErr = dep(country: Country.suisse, mois: 3.5);
    expect(chErr, isNotNull);
    expect(chErr, contains('257e CO'));
  });

  test('Flandre avant 2019 : plafond 2 (3 mois refusés)', () {
    expect(
      dep(
        country: Country.belgique,
        region: BeRegion.flandre,
        leaseDate: DateTime(2018, 6, 1),
        mois: 3,
      ),
      isNotNull,
    );
  });

  group('Bruxelles — bascule garantie au 01/11/2024 (ord. 04/04/2024)', () {
    test('bail ≥ 01/11/2024 : 3 mois bancaire REFUSÉ (max 2 toutes formes)', () {
      final err = dep(
        country: Country.belgique,
        region: BeRegion.bruxelles,
        leaseDate: DateTime(2025, 1, 1),
        mois: 3,
      );
      expect(err, isNotNull);
      expect(err, contains('248'));
      // 2 mois reste accepté.
      expect(
        dep(
          country: Country.belgique,
          region: BeRegion.bruxelles,
          leaseDate: DateTime(2025, 1, 1),
          mois: 2,
        ),
        isNull,
      );
    });
    test('bail < 01/11/2024 : 3 mois (garantie bancaire) accepté', () {
      expect(
        dep(
          country: Country.belgique,
          region: BeRegion.bruxelles,
          leaseDate: DateTime(2023, 6, 1),
          mois: 3,
        ),
        isNull,
      );
    });
  });
}
