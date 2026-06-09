import 'package:flutter_test/flutter_test.dart';
import 'package:adda_location/services/auto_backup_service.dart';

void main() {
  group('BackupFileName.tryParse', () {
    test('ancien format sans device ni secondes', () {
      final r = BackupFileName.tryParse('addalocation_2026-06-09_1430.adls');
      expect(r, isNotNull);
      expect(r!.deviceTag, isNull);
      expect(r.dateTime, DateTime(2026, 6, 9, 14, 30, 0));
    });

    test('ancien format avec secondes', () {
      final r = BackupFileName.tryParse('addalocation_2026-06-09_143005.adls');
      expect(r!.deviceTag, isNull);
      expect(r.dateTime, DateTime(2026, 6, 9, 14, 30, 5));
    });

    test('nouveau format avec tag device', () {
      final r =
          BackupFileName.tryParse('addalocation_a1b2c3d4_2026-06-09_143005.adls');
      expect(r!.deviceTag, 'a1b2c3d4');
      expect(r.dateTime, DateTime(2026, 6, 9, 14, 30, 5));
    });

    test('noms non conformes → null', () {
      expect(BackupFileName.tryParse('autre.adls'), isNull);
      expect(BackupFileName.tryParse('addalocation_2026.adls'), isNull);
      expect(BackupFileName.tryParse('addalocation_zzzz_2026-06-09_1430.adls'),
          isNull);
    });
  });

  group('BackupFileName.build', () {
    test('construit le nom attendu', () {
      final n = BackupFileName.build(
          deviceTag: 'a1b2c3d4', now: DateTime(2026, 6, 9, 14, 30, 5));
      expect(n, 'addalocation_a1b2c3d4_2026-06-09_143005.adls');
    });

    test('aller-retour build → tryParse', () {
      final dt = DateTime(2026, 1, 3, 9, 5, 7);
      final r = BackupFileName.tryParse(
          BackupFileName.build(deviceTag: 'deadbeef', now: dt));
      expect(r!.deviceTag, 'deadbeef');
      expect(r.dateTime, dt);
    });
  });

  group('ForeignBackupInfo.newestForeign', () {
    const mine = 'aaaaaaaa';

    test('nos propres fichiers sont ignorés', () {
      final r = ForeignBackupInfo.newestForeign(
        ['addalocation_aaaaaaaa_2026-06-09_100000.adls'],
        myTag: mine,
      );
      expect(r, isNull);
    });

    test('les fichiers sans tag (ancien format) sont ignorés', () {
      final r = ForeignBackupInfo.newestForeign(
        ['addalocation_2026-06-09_100000.adls'],
        myTag: mine,
      );
      expect(r, isNull);
    });

    test('détecte un fichier d\'un autre appareil', () {
      final r = ForeignBackupInfo.newestForeign(
        ['addalocation_bbbbbbbb_2026-06-09_100000.adls'],
        myTag: mine,
      );
      expect(r, isNotNull);
      expect(r!.deviceTag, 'bbbbbbbb');
      expect(r.dateTime, DateTime(2026, 6, 9, 10, 0, 0));
    });

    test('garde le plus récent parmi plusieurs étrangers', () {
      final r = ForeignBackupInfo.newestForeign(
        [
          'addalocation_bbbbbbbb_2026-06-09_080000.adls',
          'addalocation_cccccccc_2026-06-09_180000.adls',
          'addalocation_aaaaaaaa_2026-06-09_230000.adls', // le nôtre, ignoré
        ],
        myTag: mine,
      );
      expect(r!.deviceTag, 'cccccccc');
      expect(r.dateTime.hour, 18);
    });

    test('le watermark `since` exclut ce qui a déjà été importé', () {
      final files = ['addalocation_bbbbbbbb_2026-06-09_100000.adls'];
      // since = exactement la date du fichier → pas postérieur → null
      expect(
        ForeignBackupInfo.newestForeign(files,
            myTag: mine, since: DateTime(2026, 6, 9, 10, 0, 0)),
        isNull,
      );
      // since antérieur → détecté
      expect(
        ForeignBackupInfo.newestForeign(files,
            myTag: mine, since: DateTime(2026, 6, 9, 9, 59, 59)),
        isNotNull,
      );
    });
  });
}
