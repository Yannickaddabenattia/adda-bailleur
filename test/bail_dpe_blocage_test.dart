import 'package:flutter_test/flutter_test.dart';

import 'package:adda_location/core/legal/france_bail_rules.dart';
import 'package:adda_location/models/logement.dart';

/// Blocage de génération de bail selon la classe DPE (décence énergétique).
/// 📚 loi n° 2021-1104 du 22/08/2021 ; art. L. 173-1-1 CCH.
void main() {
  test('classe G + signature ≥ 01/01/2025 → génération BLOQUÉE', () {
    final err = FranceBailRules.bailDpeGError(DpeClasse.g, DateTime(2025, 3, 1));
    expect(err, isNotNull);
    expect(err, contains('2021-1104'));
  });

  test('classe G mais signature < 01/01/2025 → pas de blocage', () {
    expect(
      FranceBailRules.bailDpeGError(DpeClasse.g, DateTime(2024, 12, 31)),
      isNull,
    );
  });

  test('classes A-F → pas de blocage de génération', () {
    for (final c in [DpeClasse.a, DpeClasse.e, DpeClasse.f]) {
      expect(FranceBailRules.bailDpeGError(c, DateTime(2025, 6, 1)), isNull,
          reason: c.label);
    }
  });

  test('avertissements : F (2028) / E (2034) / classe inconnue', () {
    expect(FranceBailRules.bailDpeWarning(DpeClasse.f), contains('2028'));
    expect(FranceBailRules.bailDpeWarning(DpeClasse.e), contains('2034'));
    expect(FranceBailRules.bailDpeWarning(null), isNotNull);
    expect(FranceBailRules.bailDpeWarning(DpeClasse.c), isNull);
  });
}
