import 'package:hive_ce/hive.dart';
import 'package:uuid/uuid.dart';

import '../core/crypto/hash_service.dart';

/// Révision de loyer applicable à partir d'une date d'effet.
///
/// Permet d'historiser les changements de loyer pour un logement sans
/// perdre les anciens montants — indispensable pour générer correctement
/// les quittances rétroactives et afficher des revenus théoriques exacts
/// dans le tableau de bord financier.
class RevisionLoyer {
  final String id;
  final String logementId;
  DateTime dateEffet;
  double loyerHC;
  double charges;
  String motif;
  final DateTime createdAt;
  String? integrityHash;

  RevisionLoyer({
    required this.id,
    required this.logementId,
    required this.dateEffet,
    required this.loyerHC,
    required this.charges,
    required this.motif,
    required this.createdAt,
    this.integrityHash,
  });

  factory RevisionLoyer.create({
    required String logementId,
    required DateTime dateEffet,
    required double loyerHC,
    required double charges,
    String motif = '',
  }) {
    final now = DateTime.now().toUtc();
    final r = RevisionLoyer(
      id: const Uuid().v4(),
      logementId: logementId,
      dateEffet: DateTime(dateEffet.year, dateEffet.month, 1),
      loyerHC: loyerHC,
      charges: charges,
      motif: motif.trim(),
      createdAt: now,
    );
    r.integrityHash = r.computeIntegrityHash();
    return r;
  }

  double get total => loyerHC + charges;

  String computeIntegrityHash() {
    final payload = [
      id,
      logementId,
      dateEffet.toUtc().toIso8601String(),
      loyerHC.toStringAsFixed(2),
      charges.toStringAsFixed(2),
      motif,
      createdAt.toUtc().toIso8601String(),
    ].join('|::|');
    return HashService.sha256Hex(payload);
  }
}

class RevisionLoyerAdapter extends TypeAdapter<RevisionLoyer> {
  @override
  final int typeId = 16;

  @override
  RevisionLoyer read(BinaryReader reader) {
    final numFields = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < numFields; i++) reader.readByte(): reader.read(),
    };
    return RevisionLoyer(
      id: fields[0] as String,
      logementId: fields[1] as String,
      dateEffet: DateTime.parse(fields[2] as String),
      loyerHC: fields[3] as double,
      charges: fields[4] as double,
      motif: fields[5] as String,
      createdAt: DateTime.parse(fields[6] as String),
      integrityHash: fields[7] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, RevisionLoyer obj) {
    writer.writeByte(8);
    writer
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.logementId)
      ..writeByte(2)
      ..write(obj.dateEffet.toUtc().toIso8601String())
      ..writeByte(3)
      ..write(obj.loyerHC)
      ..writeByte(4)
      ..write(obj.charges)
      ..writeByte(5)
      ..write(obj.motif)
      ..writeByte(6)
      ..write(obj.createdAt.toUtc().toIso8601String())
      ..writeByte(7)
      ..write(obj.integrityHash);
  }
}
