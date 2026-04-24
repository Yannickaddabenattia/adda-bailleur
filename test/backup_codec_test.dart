import 'dart:typed_data';

import 'package:adda_location/core/backup/backup_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BackupCodec', () {
    test('chiffre puis déchiffre un payload avec la bonne passphrase', () {
      const payload = '{"hello":"monde","n":42}';
      const pass = 'correct horse battery staple';
      final bytes = BackupCodec.encrypt(jsonPayload: payload, passphrase: pass);
      final out = BackupCodec.decrypt(bytes: bytes, passphrase: pass);
      expect(out, payload);
    });

    test('rejette une passphrase incorrecte', () {
      const payload = '{"secret":"ultra"}';
      final bytes = BackupCodec.encrypt(
        jsonPayload: payload,
        passphrase: 'p@ssw0rd!',
      );
      expect(
        () => BackupCodec.decrypt(bytes: bytes, passphrase: 'wrong'),
        throwsA(isA<BackupDecryptionException>()),
      );
    });

    test('rejette un fichier sans le magic ADLB', () {
      final garbage = Uint8List.fromList(List<int>.generate(64, (i) => i));
      expect(
        () => BackupCodec.decrypt(bytes: garbage, passphrase: 'x'),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('deux chiffrements du même payload produisent des bytes différents', () {
      const payload = '{"a":1}';
      const pass = 'same-pass';
      final a = BackupCodec.encrypt(jsonPayload: payload, passphrase: pass);
      final b = BackupCodec.encrypt(jsonPayload: payload, passphrase: pass);
      expect(a, isNot(equals(b)));
    });
  });
}
