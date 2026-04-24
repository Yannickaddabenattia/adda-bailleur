import 'package:hive_ce/hive.dart';
import 'package:uuid/uuid.dart';

import '../core/crypto/hash_service.dart';

/// Quittance de loyer conforme à l'article 21 de la loi n°89-462 (loi ALUR).
///
/// Les montants sont figés au moment de la création (snapshot) pour rester
/// immuables même si le loyer du logement est modifié plus tard.
class Quittance {
  final String id;
  final String logementId;
  final String locataireId;
  final int periodYear;
  final int periodMonth;
  final double loyerHC;
  final double charges;
  final DateTime datePaiement;
  final DateTime dateEmission;
  String notes;
  final DateTime createdAt;
  String? integrityHash;

  Quittance({
    required this.id,
    required this.logementId,
    required this.locataireId,
    required this.periodYear,
    required this.periodMonth,
    required this.loyerHC,
    required this.charges,
    required this.datePaiement,
    required this.dateEmission,
    required this.notes,
    required this.createdAt,
    this.integrityHash,
  });

  factory Quittance.create({
    required String logementId,
    required String locataireId,
    required int periodYear,
    required int periodMonth,
    required double loyerHC,
    required double charges,
    required DateTime datePaiement,
    String notes = '',
  }) {
    final now = DateTime.now().toUtc();
    final q = Quittance(
      id: const Uuid().v4(),
      logementId: logementId,
      locataireId: locataireId,
      periodYear: periodYear,
      periodMonth: periodMonth,
      loyerHC: loyerHC,
      charges: charges,
      datePaiement: datePaiement,
      dateEmission: now,
      notes: notes.trim(),
      createdAt: now,
    );
    q.integrityHash = q.computeIntegrityHash();
    return q;
  }

  double get total => loyerHC + charges;

  /// Premier jour de la période (1er du mois).
  DateTime get periodStart => DateTime(periodYear, periodMonth, 1);

  /// Dernier jour de la période.
  DateTime get periodEnd => DateTime(periodYear, periodMonth + 1, 0);

  String get periodLabel {
    const mois = [
      'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
      'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
    ];
    return '${mois[periodMonth - 1]} $periodYear';
  }

  String computeIntegrityHash() {
    final payload = [
      id,
      logementId,
      locataireId,
      periodYear.toString(),
      periodMonth.toString(),
      loyerHC.toStringAsFixed(2),
      charges.toStringAsFixed(2),
      datePaiement.toUtc().toIso8601String(),
      dateEmission.toUtc().toIso8601String(),
      notes.trim(),
      createdAt.toUtc().toIso8601String(),
    ].join('|::|');
    return HashService.sha256Hex(payload);
  }

  bool verifyIntegrity() {
    if (integrityHash == null) return false;
    return computeIntegrityHash() == integrityHash;
  }
}

class QuittanceAdapter extends TypeAdapter<Quittance> {
  @override
  final int typeId = 8;

  @override
  Quittance read(BinaryReader reader) {
    final numFields = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < numFields; i++) reader.readByte(): reader.read(),
    };
    return Quittance(
      id: fields[0] as String,
      logementId: fields[1] as String,
      locataireId: fields[2] as String,
      periodYear: fields[3] as int,
      periodMonth: fields[4] as int,
      loyerHC: fields[5] as double,
      charges: fields[6] as double,
      datePaiement: DateTime.parse(fields[7] as String),
      dateEmission: DateTime.parse(fields[8] as String),
      notes: fields[9] as String,
      createdAt: DateTime.parse(fields[10] as String),
      integrityHash: fields[11] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, Quittance obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.logementId)
      ..writeByte(2)
      ..write(obj.locataireId)
      ..writeByte(3)
      ..write(obj.periodYear)
      ..writeByte(4)
      ..write(obj.periodMonth)
      ..writeByte(5)
      ..write(obj.loyerHC)
      ..writeByte(6)
      ..write(obj.charges)
      ..writeByte(7)
      ..write(obj.datePaiement.toUtc().toIso8601String())
      ..writeByte(8)
      ..write(obj.dateEmission.toUtc().toIso8601String())
      ..writeByte(9)
      ..write(obj.notes)
      ..writeByte(10)
      ..write(obj.createdAt.toUtc().toIso8601String())
      ..writeByte(11)
      ..write(obj.integrityHash);
  }
}
