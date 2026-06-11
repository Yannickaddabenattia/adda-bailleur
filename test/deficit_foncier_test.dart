import 'package:flutter_test/flutter_test.dart';

import 'package:adda_location/services/fiscalite_service.dart';

/// Déficit foncier imputable sur le revenu global.
/// 📚 CGI art. 156, I-3° ; décret n° 2023-297 du 21/04/2023 (plafond majoré
/// rénovation énergétique, dépenses payées du 01/01/2023 au 31/12/2025).
void main() {
  test('plafond standard 10 700 € sans rénovation', () {
    expect(
      BaremeIR2026.plafondDeficitImputable(2024, renovationEnergetique: false),
      10700,
    );
  });

  test('plafond majoré 21 400 € si rénovation ET fenêtre 2023-2025', () {
    expect(
      BaremeIR2026.plafondDeficitImputable(2023, renovationEnergetique: true),
      21400,
    );
    expect(
      BaremeIR2026.plafondDeficitImputable(2025, renovationEnergetique: true),
      21400,
    );
  });

  test('hors fenêtre (2026/2022) → 10 700 € (prorogation 2027 NON codée)', () {
    expect(
      BaremeIR2026.plafondDeficitImputable(2026, renovationEnergetique: true),
      10700,
    );
    expect(
      BaremeIR2026.plafondDeficitImputable(2022, renovationEnergetique: true),
      10700,
    );
  });

  test('date de fin du plafond majoré paramétrée au 31/12/2025', () {
    expect(BaremeIR2026.dateFinPlafondMajore, DateTime(2025, 12, 31));
  });
}
