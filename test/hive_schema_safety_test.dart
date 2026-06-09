import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Garde-fou « aucune perte de données lors d'une mise à jour ».
///
/// La persistance Hive repose sur deux invariants ; les enfreindre lors d'une
/// évolution du schéma corromprait SILENCIEUSEMENT les données existantes des
/// utilisateurs après une mise à jour :
///   1. chaque `typeId` d'adaptateur est unique dans tout le projet ;
///   2. dans un adaptateur, aucun index de champ (`writeByte(n)`) n'est
///      réutilisé (les nouveaux champs prennent des index neufs).
///
/// Ce test échoue si une future modification casse l'un de ces invariants.
void main() {
  final modelFiles = Directory('lib/models')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  test('les modèles sont bien présents', () {
    expect(modelFiles, isNotEmpty);
  });

  test('typeId Hive uniques dans tout le projet', () {
    final seen = <int, String>{};
    final re = RegExp(r'final int typeId = (\d+);');
    for (final f in modelFiles) {
      for (final m in re.allMatches(f.readAsStringSync())) {
        final id = int.parse(m.group(1)!);
        expect(
          seen.containsKey(id),
          isFalse,
          reason: 'typeId $id en double : ${f.path} ET ${seen[id]} — '
              'corromprait les données après mise à jour.',
        );
        seen[id] = f.path;
      }
    }
    expect(seen.length, greaterThan(15), reason: 'trop peu d\'adaptateurs vus');
  });

  test('index de champ (writeByte) non réutilisés dans chaque adaptateur', () {
    final classRe = RegExp(r'class (\w+Adapter) extends TypeAdapter');
    final wbRe = RegExp(r'writeByte\((\d+)\)');
    for (final f in modelFiles) {
      final content = f.readAsStringSync();
      final classes = classRe.allMatches(content).toList();
      for (var i = 0; i < classes.length; i++) {
        final start = classes[i].start;
        final end =
            i + 1 < classes.length ? classes[i + 1].start : content.length;
        final segment = content.substring(start, end);
        final name = classes[i].group(1)!;
        final nums = wbRe
            .allMatches(segment)
            .map((m) => int.parse(m.group(1)!))
            .toList();
        if (nums.isEmpty) continue;
        // Le 1er writeByte est le compteur de champs (toujours > tout index de
        // champ), les autres sont les index ; tous doivent être distincts.
        expect(
          nums.toSet().length,
          nums.length,
          reason: '$name (${f.path}) : index writeByte réutilisé — '
              'corromprait les anciennes données après mise à jour.',
        );
      }
    }
  });
}
