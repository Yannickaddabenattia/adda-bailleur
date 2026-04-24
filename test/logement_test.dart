import 'package:adda_location/models/logement.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Logement', () {
    test('create normalise les champs et génère un id', () {
      final l = Logement.create(
        libelle: '  Appart Paris ',
        adresse: ' 12 rue X ',
        codePostal: '75001',
        ville: 'Paris',
        type: LogementType.appartement,
        surface: 42.5,
        nbPieces: 2,
        loyerHC: 900,
        charges: 60,
      );
      expect(l.libelle, 'Appart Paris');
      expect(l.adresse, '12 rue X');
      expect(l.id.isNotEmpty, isTrue);
      expect(l.equipements, isEmpty);
    });

    test('loyerTTC additionne HC + charges', () {
      final l = Logement.create(
        libelle: 'A',
        adresse: 'a',
        codePostal: '75001',
        ville: 'Paris',
        type: LogementType.studio,
        surface: 25,
        nbPieces: 1,
        loyerHC: 700,
        charges: 45,
      );
      expect(l.loyerTTC, 745);
    });

    test('adresseComplete concatène adresse, CP et ville', () {
      final l = Logement.create(
        libelle: 'A',
        adresse: '5 rue du Test',
        codePostal: '75001',
        ville: 'Paris',
        type: LogementType.maison,
        surface: 100,
        nbPieces: 4,
        loyerHC: 1500,
        charges: 150,
      );
      expect(l.adresseComplete, '5 rue du Test, 75001 Paris');
    });
  });

  group('LogementType', () {
    test('fromString reconnaît les valeurs valides', () {
      expect(LogementType.fromString('appartement'), LogementType.appartement);
      expect(LogementType.fromString('maison'), LogementType.maison);
      expect(LogementType.fromString('studio'), LogementType.studio);
    });

    test('fromString fallback sur autre si inconnu', () {
      expect(LogementType.fromString('palace'), LogementType.autre);
    });

    test('label renvoie le libellé français', () {
      expect(LogementType.appartement.label, 'Appartement');
      expect(LogementType.maison.label, 'Maison');
    });
  });
}
