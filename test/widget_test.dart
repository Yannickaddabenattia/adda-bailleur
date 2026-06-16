import 'package:adda_location/core/crypto/hash_service.dart';
import 'package:adda_location/models/user_profile.dart';
import 'package:adda_location/models/user_role.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HashService', () {
    test('sha256Hex retourne un hash stable de 64 caractères hexadécimaux', () {
      final hash = HashService.sha256Hex('adda-location');
      expect(hash.length, 64);
      expect(RegExp(r'^[a-f0-9]+$').hasMatch(hash), isTrue);
      expect(HashService.sha256Hex('adda-location'), hash);
    });

    test('userIntegrityHash est insensible aux espaces et à la casse email', () {
      final date = DateTime.parse('2026-04-21T10:00:00Z');
      final h1 = HashService.userIntegrityHash(
        role: 'proprietaire',
        firstName: 'Yannick',
        lastName: 'ADDA',
        email: 'yannickpamal@aol.com',
        createdAt: date,
      );
      final h2 = HashService.userIntegrityHash(
        role: 'proprietaire',
        firstName: 'Yannick',
        lastName: 'ADDA',
        email: 'YannickPamal@AOL.com',
        createdAt: date,
      );
      expect(h1, h2);
    });

    test('userIntegrityHash change si un champ immuable change', () {
      final date = DateTime.parse('2026-04-21T10:00:00Z');
      final base = HashService.userIntegrityHash(
        role: 'proprietaire',
        firstName: 'Yannick',
        lastName: 'ADDA',
        email: 'a@b.com',
        createdAt: date,
      );
      final changedRole = HashService.userIntegrityHash(
        role: 'locataire',
        firstName: 'Yannick',
        lastName: 'ADDA',
        email: 'a@b.com',
        createdAt: date,
      );
      final changedName = HashService.userIntegrityHash(
        role: 'proprietaire',
        firstName: 'Yannick',
        lastName: 'BENATTIA',
        email: 'a@b.com',
        createdAt: date,
      );
      expect(changedRole, isNot(base));
      expect(changedName, isNot(base));
    });
  });

  group('UserProfile', () {
    test('create normalise prénom et nom (MAJ)', () {
      final profile = UserProfile.create(
        role: UserRole.proprietaire,
        firstName: '  Yannick ',
        lastName: ' adda ',
      );
      expect(profile.firstName, 'Yannick');
      expect(profile.lastName, 'ADDA');
      expect(profile.email, ''); // plus d'e-mail collecté (Apple 5.1.1(v))
      expect(profile.id.isNotEmpty, isTrue);
    });

    test('verifyIntegrity renvoie true sur un profil fraîchement créé', () {
      final profile = UserProfile.create(
        role: UserRole.locataire,
        firstName: 'Jean',
        lastName: 'Dupont',
      );
      expect(profile.verifyIntegrity(), isTrue);
    });

    test('fullName concatène prénom et nom', () {
      final profile = UserProfile.create(
        role: UserRole.proprietaire,
        firstName: 'Yannick',
        lastName: 'Adda',
      );
      expect(profile.fullName, 'Yannick ADDA');
    });
  });

  group('UserRole', () {
    test('fromString reconnaît les valeurs valides', () {
      expect(UserRole.fromString('proprietaire'), UserRole.proprietaire);
      expect(UserRole.fromString('locataire'), UserRole.locataire);
    });

    test('fromString rejette les valeurs invalides', () {
      expect(
        () => UserRole.fromString('admin'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('label retourne le libellé français', () {
      expect(UserRole.proprietaire.label, 'Propriétaire');
      expect(UserRole.locataire.label, 'Locataire');
    });
  });
}
