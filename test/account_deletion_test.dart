import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:adda_location/core/storage/local_database.dart';

/// Suppression de compte (Apple 5.1.1(v)) — volet « fichiers hors Hive ».
///
/// La suppression des boxes Hive ne touche pas les fichiers rangés sous le
/// répertoire documents (photos d'état des lieux, PDF de baux, justificatifs,
/// snapshots d'avant migration…). [LocalDatabase.wipeUserFiles] doit purger
/// tout ce périmètre, sinon des données personnelles survivraient à la
/// suppression de compte.
void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('adda_delete_');
  });
  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  void seed(String dir, String file, String contents) {
    final d = Directory('${tmp.path}/$dir')..createSync(recursive: true);
    File('${d.path}/$file').writeAsStringSync(contents);
  }

  test('purge TOUS les dossiers de fichiers utilisateur connus', () async {
    // On sème un fichier (avec une sous-arborescence pour `plans`) dans chaque
    // dossier déclaré, puis on vérifie qu'aucun ne survit.
    for (final dir in LocalDatabase.userFileDirs) {
      seed(dir, 'donnee_perso.dat', 'nom + adresse + signature locataire');
    }
    seed('plans/plan-1/walls', 'mur.png', 'image'); // sous-dossier imbriqué

    await LocalDatabase.wipeUserFiles(tmp.path);

    for (final dir in LocalDatabase.userFileDirs) {
      expect(Directory('${tmp.path}/$dir').existsSync(), isFalse,
          reason: 'le dossier "$dir" aurait dû être supprimé');
    }
  });

  test('ne supprime QUE le périmètre connu (pas de purge sauvage)', () async {
    seed('photos', 'a.jpg', 'x');
    seed('un_autre_dossier', 'garde-moi.txt', 'hors périmètre');

    await LocalDatabase.wipeUserFiles(tmp.path);

    expect(Directory('${tmp.path}/photos').existsSync(), isFalse);
    expect(
      Directory('${tmp.path}/un_autre_dossier').existsSync(),
      isTrue,
      reason: 'un dossier hors liste ne doit pas être touché',
    );
  });

  test('best-effort : aucun dossier présent → ne lève pas', () async {
    await expectLater(LocalDatabase.wipeUserFiles(tmp.path), completes);
  });

  test('idempotent : un second appel ne lève pas', () async {
    seed('contrats', 'bail.pdf', 'pdf');
    await LocalDatabase.wipeUserFiles(tmp.path);
    await expectLater(LocalDatabase.wipeUserFiles(tmp.path), completes);
    expect(Directory('${tmp.path}/contrats').existsSync(), isFalse);
  });

  test('inclut les snapshots d\'avant migration et les backups reçus', () async {
    // Garde-fous explicites : ces deux dossiers contiennent des copies
    // complètes des données et doivent impérativement être purgés.
    expect(LocalDatabase.userFileDirs, contains('pre_update_backups'));
    expect(LocalDatabase.userFileDirs, contains('ADDA Bailleur document'));
  });
}
