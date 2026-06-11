import 'package:flutter_test/flutter_test.dart';

import 'package:adda_location/core/legal/france_bail_rules.dart';

/// Acte de caution — cumul caution + assurance loyers impayés (GLI).
/// 📚 loi n° 89-462, art. 22-1, al. 1er (cumul interdit, sauf étudiant/apprenti).
///
/// NB : la conformité de l'ACTE lui-même (zone vide art. 2297 non pré-remplie,
/// reproduction verbatim de l'avant-dernier alinéa de l'art. 22-1, loyer +
/// révision repris) est dans `contrat_bail_annexes_pdf.dart` (QA manuelle du PDF).
void main() {
  test('cumul GLI + caution INTERDIT (art. 22-1 al. 1er)', () {
    final err = FranceBailRules.cautionGliError(
      assuranceLoyersImpayes: true,
      locataireEtudiantApprenti: false,
    );
    expect(err, isNotNull);
    expect(err, contains('22-1'));
  });

  test('exception : locataire étudiant ou apprenti → cumul autorisé', () {
    expect(
      FranceBailRules.cautionGliError(
        assuranceLoyersImpayes: true,
        locataireEtudiantApprenti: true,
      ),
      isNull,
    );
  });

  test('pas de GLI → pas de blocage', () {
    expect(
      FranceBailRules.cautionGliError(
        assuranceLoyersImpayes: false,
        locataireEtudiantApprenti: false,
      ),
      isNull,
    );
  });

  group('Formalités de l\'acte (art. 22-1 / 2297, à peine de nullité)', () {
    test('titre de la zone : « article 2297 du Code civil », JAMAIS 2288', () {
      expect(FranceBailRules.cautionMentionTitre,
          contains('2297 du Code civil'));
      expect(FranceBailRules.cautionMentionTitre.contains('2288'), isFalse);
    });

    test('consigne 2297 verbatim (montant en toutes lettres ET en chiffres)',
        () {
      expect(FranceBailRules.cautionMention2297, contains('À peine de nullité'));
      expect(FranceBailRules.cautionMention2297,
          contains('en toutes lettres et en chiffres'));
      expect(FranceBailRules.cautionMention2297,
          contains('la somme écrite en toutes lettres'));
    });

    test('avant-dernier alinéa art. 22-1 verbatim (faculté de résiliation)', () {
      expect(FranceBailRules.cautionResiliationAlinea,
          contains('résilier unilatéralement'));
      expect(FranceBailRules.cautionResiliationAlinea,
          contains('notification de la résiliation'));
    });

    test('aucune référence 2288 ni formule pré-remplie pré-2022', () {
      for (final t in [
        FranceBailRules.cautionMentionTitre,
        FranceBailRules.cautionMention2297,
        FranceBailRules.cautionResiliationAlinea,
      ]) {
        expect(t.contains('2288'), isFalse);
        // Zone de mention VIDE : aucune mention pré-rédigée à la place de la caution.
        expect(t.toLowerCase().contains('je soussign'), isFalse);
        expect(t.toLowerCase().contains('me porte caution'), isFalse);
      }
    });
  });
}
