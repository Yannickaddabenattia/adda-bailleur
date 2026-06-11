import 'package:flutter_test/flutter_test.dart';

import 'package:adda_location/models/logement.dart';
import 'package:adda_location/services/revision_loyer_service.dart';

/// Gel des loyers des passoires énergétiques (révision IRL).
/// 📚 loi n° 2021-1104 du 22/08/2021 (Climat et Résilience), art. L. 173-1-1 CCH
/// — depuis le 24/08/2022, aucune hausse de loyer pour un logement classé F/G.
void main() {
  test('révision INTERDITE pour F et G (gel depuis 24/08/2022)', () {
    final f = RevisionLoyerService.gelRevisionError(DpeClasse.f);
    final g = RevisionLoyerService.gelRevisionError(DpeClasse.g);
    expect(f, isNotNull);
    expect(g, isNotNull);
    expect(f, contains('2021-1104')); // anti-réversion
  });

  test('révision AUTORISÉE pour A à E', () {
    for (final c in [
      DpeClasse.a,
      DpeClasse.b,
      DpeClasse.c,
      DpeClasse.d,
      DpeClasse.e,
    ]) {
      expect(RevisionLoyerService.gelRevisionError(c), isNull, reason: c.label);
    }
  });

  test('classe inconnue (null) → pas de blocage mais avertissement', () {
    expect(RevisionLoyerService.gelRevisionError(null), isNull);
    expect(RevisionLoyerService.dpeInconnu(null), isTrue);
    expect(RevisionLoyerService.dpeInconnu(DpeClasse.c), isFalse);
  });

  test('estPassoire : F/G oui, A-E non', () {
    expect(DpeClasse.f.estPassoire, isTrue);
    expect(DpeClasse.g.estPassoire, isTrue);
    expect(DpeClasse.e.estPassoire, isFalse);
  });
}
