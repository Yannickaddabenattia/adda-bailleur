import 'package:adda_location/models/locataire.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Locataire', () {
    test('create normalise nom (MAJ) et email (min)', () {
      final l = Locataire.create(
        firstName: '  Jean ',
        lastName: ' dupont ',
        email: ' Jean@Mail.COM ',
      );
      expect(l.firstName, 'Jean');
      expect(l.lastName, 'DUPONT');
      expect(l.email, 'jean@mail.com');
    });

    test('phone vide est stocké comme null', () {
      final l = Locataire.create(
        firstName: 'A',
        lastName: 'B',
        email: 'a@b.com',
        phone: '   ',
      );
      expect(l.phone, isNull);
    });

    test('phone non vide est conservé trimé', () {
      final l = Locataire.create(
        firstName: 'A',
        lastName: 'B',
        email: 'a@b.com',
        phone: ' 0612345678 ',
      );
      expect(l.phone, '0612345678');
    });

    test('logementIds commence par une copie modifiable', () {
      final ids = <String>['l1', 'l2'];
      final l = Locataire.create(
        firstName: 'A',
        lastName: 'B',
        email: 'a@b.com',
        logementIds: ids,
      );
      l.logementIds.add('l3');
      expect(l.logementIds, ['l1', 'l2', 'l3']);
      expect(ids, ['l1', 'l2']); // la liste d'origine n'est pas modifiée
    });

    test('fullName concatène prénom et nom', () {
      final l = Locataire.create(
        firstName: 'Jean',
        lastName: 'Dupont',
        email: 'a@b.com',
      );
      expect(l.fullName, 'Jean DUPONT');
    });
  });
}
