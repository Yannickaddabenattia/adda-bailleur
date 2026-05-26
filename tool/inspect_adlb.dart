import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../lib/core/backup/backup_codec.dart';
import '../lib/models/plan_logement.dart';

/// Décrypte un .adlb et affiche le contenu (clés, taille, nb plans).
/// Usage : dart run tool/inspect_adlb.dart <chemin.adlb> <passphrase>
void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln('Usage : dart run tool/inspect_adlb.dart <fichier.adlb> <passphrase>');
    exit(64);
  }
  final file = File(args[0]);
  if (!file.existsSync()) {
    stderr.writeln('Fichier introuvable : ${args[0]}');
    exit(66);
  }
  final bytes = Uint8List.fromList(file.readAsBytesSync());
  final passphrase = args[1];

  final json = BackupCodec.decrypt(bytes: bytes, passphrase: passphrase);
  final decoded = jsonDecode(json) as Map<String, dynamic>;

  stdout.writeln('Fichier : ${args[0]}');
  stdout.writeln('Taille chiffrée : ${bytes.length} octets');
  stdout.writeln('Taille JSON déchiffré : ${json.length} caractères');
  stdout.writeln('Clés présentes : ${decoded.keys.toList()}');
  stdout.writeln('Version : ${decoded['version']}');
  for (final key in [
    'profile',
    'logements',
    'locataires',
    'etatsDesLieux',
    'quittances',
    'plans',
  ]) {
    final value = decoded[key];
    if (value is List) {
      stdout.writeln('$key : ${value.length} entrée(s)');
      if (key == 'plans') {
        for (final p in value) {
          if (p is Map) {
            final rooms = (p['rooms'] as List?)?.length ?? 0;
            final ann = (p['annotations'] as List?)?.length ?? 0;
            final photos = (p['wallPhotos'] as List?)?.length ?? 0;
            stdout.writeln(
                '  - id=${p['id']} logementId=${p['logementId']} '
                'rooms=$rooms annotations=$ann wallPhotos=$photos '
                'sortOrder=${p['sortOrder']} kind=${p['kind']}');
            try {
              PlanLogement.fromMap(p.cast<String, dynamic>());
              stdout.writeln('    -> fromMap OK');
            } catch (e, st) {
              stdout.writeln('    -> fromMap THROWS : $e');
              stdout.writeln(st);
            }
          }
        }
      }
    } else if (value == null) {
      stdout.writeln('$key : ABSENT');
    } else {
      stdout.writeln('$key : présent');
    }
  }
}
