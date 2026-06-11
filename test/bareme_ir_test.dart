import 'package:flutter_test/flutter_test.dart';

import 'package:adda_location/services/fiscalite_service.dart';

/// Barème IR millésime 2026 (revenus 2025) + plafond du quotient familial.
/// 📚 LF pour 2026, art. 4 (+0,9 %) ; BOFiP BOI-IR-LIQ-20-10 §40 ; art. 197 CGI.
void main() {
  group('Barème IR — revenus 2025', () {
    test('tranches officielles', () {
      final t = BaremeIR2026.tranchesPour(2025);
      expect(t[0].$1, 11600);
      expect(t[0].$2, 0.00);
      expect(t[1].$1, 29579);
      expect(t[1].$2, 0.11);
      expect(t[2].$1, 84577);
      expect(t[2].$2, 0.30);
      expect(t[3].$1, 181917);
      expect(t[3].$2, 0.41);
      expect(t.last.$2, 0.45);
    });
  });

  group('Plafond du quotient familial par année (art. 197 CGI)', () {
    test('valeurs LF 2026', () {
      expect(BaremeIR2026.plafondQFPour(2023), 1759);
      expect(BaremeIR2026.plafondQFPour(2024), 1791); // PAS 1790
      expect(BaremeIR2026.plafondQFPour(2025), 1807);
    });
    test('année hors table → dernier millésime connu (2025)', () {
      expect(BaremeIR2026.plafondQFPour(2030), 1807);
    });
  });
}
