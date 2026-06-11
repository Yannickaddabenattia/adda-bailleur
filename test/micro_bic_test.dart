import 'package:flutter_test/flutter_test.dart';

import 'package:adda_location/services/fiscalite_service.dart';

/// Micro-BIC — réforme « Le Meur ».
/// 📚 loi n° 2024-1039 du 19/11/2024, art. 50-0 CGI (1re application : revenus
/// 2025 déclarés en 2026).
void main() {
  test('tourisme CLASSÉ : 71 %/188 700 € (≤2024), 50 %/77 700 € (≥2025)', () {
    expect(BaremeIR2026.abattementMicroBICTourismeClasse(2024), 0.71);
    expect(BaremeIR2026.seuilMicroBICTourismeClasse(2024), 188700);
    expect(BaremeIR2026.abattementMicroBICTourismeClasse(2025), 0.50);
    expect(BaremeIR2026.seuilMicroBICTourismeClasse(2025), 77700);
  });

  test('tourisme NON classé : 50 %/77 700 € (≤2024), 30 %/15 000 € (≥2025)', () {
    expect(BaremeIR2026.abattementMicroBICTourismeNonClasse(2024), 0.50);
    expect(BaremeIR2026.seuilMicroBICTourismeNonClasse(2024), 77700);
    expect(BaremeIR2026.abattementMicroBICTourismeNonClasse(2025), 0.30);
    expect(BaremeIR2026.seuilMicroBICTourismeNonClasse(2025), 15000);
  });

  test('meublé longue durée 50 %/77 700 € inchangé ; plancher 305 € (inchangé)',
      () {
    expect(BaremeIR2026.abattementMicroBIC, 0.50);
    expect(BaremeIR2026.seuilMicroBIC, 77700);
    expect(BaremeIR2026.plancherMicroBIC, 305);
  });
}
