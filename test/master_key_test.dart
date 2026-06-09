import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:adda_location/services/master_key_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MasterKeyService.computeVerifier (Argon2id)', () {
    final salt = Uint8List.fromList(List.filled(16, 7));

    test('déterministe : même mot de passe + même sel → même hash', () async {
      final h1 = await MasterKeyService.computeVerifier('motDePasse!23', salt);
      final h2 = await MasterKeyService.computeVerifier('motDePasse!23', salt);
      expect(h1, equals(h2));
      expect(h1.length, 32);
    });

    test('sensible au mot de passe', () async {
      final h1 = await MasterKeyService.computeVerifier('motDePasse!23', salt);
      final h2 = await MasterKeyService.computeVerifier('motDePasse!24', salt);
      expect(h1, isNot(equals(h2)));
    });

    test('sensible au sel', () async {
      final h1 = await MasterKeyService.computeVerifier('motDePasse!23', salt);
      final h2 = await MasterKeyService.computeVerifier(
          'motDePasse!23', Uint8List.fromList(List.filled(16, 8)));
      expect(h1, isNot(equals(h2)));
    });
  });
}
