import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:adda_location/core/storage/local_database.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('adda_snap_');
  });
  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  void writeMarker(String v) =>
      File('${tmp.path}/.adda_data_version').writeAsStringSync(v);
  void writeHive(String name, String data) =>
      File('${tmp.path}/$name').writeAsStringSync(data);

  test('premier lancement (pas de marqueur) → aucun snapshot', () async {
    writeHive('logements.hive', 'data');
    final snap = await LocalDatabase.snapshotBeforeUpgrade(
        dirPath: tmp.path, currentVersion: '1.1.0', nowStamp: 'S1');
    expect(snap, isNull);
  });

  test('changement de version → snapshot des .hive uniquement', () async {
    writeMarker('1.0.0');
    writeHive('logements.hive', 'A');
    writeHive('locataires.hive', 'B');
    writeHive('settings.hive', 'C');

    final snap = await LocalDatabase.snapshotBeforeUpgrade(
        dirPath: tmp.path, currentVersion: '1.1.0', nowStamp: 'S2');

    expect(snap, isNotNull);
    expect(snap!.path, endsWith('S2__v1.0.0'));
    expect(File('${snap.path}/logements.hive').existsSync(), isTrue);
    expect(File('${snap.path}/locataires.hive').readAsStringSync(), 'B');
    expect(File('${snap.path}/settings.hive').readAsStringSync(), 'C');
    // le marqueur de version n'est pas copié (pas un .hive)
    expect(File('${snap.path}/.adda_data_version').existsSync(), isFalse);
    // snapshotBeforeUpgrade ne met PAS à jour le marqueur (fait après migrations)
    expect(File('${tmp.path}/.adda_data_version').readAsStringSync(), '1.0.0');
  });

  test('même version → aucun snapshot', () async {
    writeMarker('1.1.0');
    writeHive('logements.hive', 'A');
    final snap = await LocalDatabase.snapshotBeforeUpgrade(
        dirPath: tmp.path, currentVersion: '1.1.0', nowStamp: 'S3');
    expect(snap, isNull);
  });

  test('aucun .hive → aucun snapshot même si la version change', () async {
    writeMarker('1.0.0');
    final snap = await LocalDatabase.snapshotBeforeUpgrade(
        dirPath: tmp.path, currentVersion: '1.1.0', nowStamp: 'S4');
    expect(snap, isNull);
  });

  test('recordCurrentVersion écrit bien le marqueur', () async {
    await LocalDatabase.recordCurrentVersion(tmp.path, '1.2.0');
    expect(File('${tmp.path}/.adda_data_version').readAsStringSync(), '1.2.0');
  });

  test('purge : ne conserve que les N plus récents', () async {
    writeMarker('1.0.0');
    writeHive('logements.hive', 'A');
    for (final s in [
      '2026-01-01',
      '2026-02-01',
      '2026-03-01',
      '2026-04-01',
      '2026-05-01',
    ]) {
      await LocalDatabase.snapshotBeforeUpgrade(
          dirPath: tmp.path, currentVersion: '1.1.0', nowStamp: s, keepLast: 2);
    }
    final root = Directory('${tmp.path}/pre_update_backups');
    final names = root
        .listSync()
        .whereType<Directory>()
        .map((d) => d.path.split(Platform.pathSeparator).last)
        .toList();
    expect(names.length, 2);
    expect(names.any((n) => n.contains('2026-05-01')), isTrue);
    expect(names.any((n) => n.contains('2026-04-01')), isTrue);
    expect(names.any((n) => n.contains('2026-01-01')), isFalse);
  });
}
