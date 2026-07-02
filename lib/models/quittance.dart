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

  /// Snapshot du nom du bailleur au moment du partage.
  /// Présent uniquement sur les quittances importées via partage locataire.
  /// Permet à l'app locataire d'afficher le bon bailleur sur le PDF
  /// au lieu de réutiliser son propre UserProfile.
  String? bailleurName;
  String? bailleurEmail;

  /// Montant réellement encaissé pour cette quittance. Par défaut = total
  /// (loyer HC + charges). Peut être inférieur (paiement partiel) ou
  /// supérieur (avance / régularisation passée incluse dans ce versement).
  /// Si null à la lecture (anciennes quittances), on retombe sur `total`.
  double? montantPaye;

  /// Versements supplémentaires alloués à d'autres mois — régularisations
  /// de mois passés impayés OU avance sur des mois suivants.
  /// Clé : "YYYY-MM" (ex. "2026-02"). Valeur : montant alloué à ce mois.
  /// La somme `montantPaye + versementsSupplementaires.values` représente
  /// l'argent total encaissé via cette quittance.
  Map<String, double> versementsSupplementaires;

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
    this.bailleurName,
    this.bailleurEmail,
    this.montantPaye,
    Map<String, double>? versementsSupplementaires,
  }) : versementsSupplementaires = versementsSupplementaires ?? {};

  factory Quittance.create({
    required String logementId,
    required String locataireId,
    required int periodYear,
    required int periodMonth,
    required double loyerHC,
    required double charges,
    required DateTime datePaiement,
    String notes = '',
    double? montantPaye,
    Map<String, double>? versementsSupplementaires,
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
      montantPaye: montantPaye,
      versementsSupplementaires: versementsSupplementaires,
    );
    q.integrityHash = q.computeIntegrityHash();
    return q;
  }

  /// Construit une nouvelle quittance basée sur [original] avec les champs
  /// modifiables remplacés. L'id, le logement, le locataire, la date d'émission
  /// et la date de création sont préservés. Le hash d'intégrité est recalculé.
  factory Quittance.edit({
    required Quittance original,
    required int periodYear,
    required int periodMonth,
    required double loyerHC,
    required double charges,
    required DateTime datePaiement,
    String? notes,
    double? montantPaye,
    Map<String, double>? versementsSupplementaires,
  }) {
    final q = Quittance(
      id: original.id,
      logementId: original.logementId,
      locataireId: original.locataireId,
      periodYear: periodYear,
      periodMonth: periodMonth,
      loyerHC: loyerHC,
      charges: charges,
      datePaiement: datePaiement,
      dateEmission: original.dateEmission,
      notes: (notes ?? original.notes).trim(),
      createdAt: original.createdAt,
      bailleurName: original.bailleurName,
      bailleurEmail: original.bailleurEmail,
      montantPaye: montantPaye ?? original.montantPaye,
      versementsSupplementaires:
          versementsSupplementaires ?? original.versementsSupplementaires,
    );
    q.integrityHash = q.computeIntegrityHash();
    return q;
  }

  double get total => loyerHC + charges;

  /// Montant effectivement encaissé pour la PÉRIODE de cette quittance.
  /// Si non renseigné explicitement, on suppose que le total a été payé
  /// (rétro-compat avec les quittances créées avant l'ajout du champ).
  double get montantPayePeriode => montantPaye ?? total;

  /// Total des versements supplémentaires (alloués à d'autres mois).
  double get totalVersementsSupplementaires =>
      versementsSupplementaires.values.fold<double>(0, (s, v) => s + v);

  /// Montant total réellement encaissé via cette quittance (période + autres).
  double get montantEncaisseTotal =>
      montantPayePeriode + totalVersementsSupplementaires;

  /// Restant dû pour LA PÉRIODE de cette quittance (≥ 0).
  double get restantDuPeriode {
    final diff = total - montantPayePeriode;
    return diff > 0 ? diff : 0;
  }

  /// Paiement partiel de la période → le document vaut reçu, pas quittance
  /// (article 21 de la loi du 6 juillet 1989). Tolérance d'un centime.
  bool get isPaiementPartiel => restantDuPeriode > 0.01;

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
    // Sérialisation déterministe des versements supplémentaires (clés triées).
    final keys = versementsSupplementaires.keys.toList()..sort();
    final versementsStr = keys
        .map((k) => '$k=${versementsSupplementaires[k]!.toStringAsFixed(2)}')
        .join(';');
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
      montantPaye?.toStringAsFixed(2) ?? '',
      versementsStr,
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
    final rawVers = fields[15] as Map?;
    final vers = <String, double>{};
    if (rawVers != null) {
      rawVers.forEach((k, v) {
        if (k is String && v is num) vers[k] = v.toDouble();
      });
    }
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
      bailleurName: fields[12] as String?,
      bailleurEmail: fields[13] as String?,
      montantPaye: (fields[14] as num?)?.toDouble(),
      versementsSupplementaires: vers,
    );
  }

  @override
  void write(BinaryWriter writer, Quittance obj) {
    final hasSnapshot =
        obj.bailleurName != null || obj.bailleurEmail != null;
    final hasMontantPaye = obj.montantPaye != null;
    final hasVersements = obj.versementsSupplementaires.isNotEmpty;
    final count = 12 +
        (hasSnapshot ? 2 : 0) +
        (hasMontantPaye ? 1 : 0) +
        (hasVersements ? 1 : 0);
    writer.writeByte(count);
    writer
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
    if (hasSnapshot) {
      writer
        ..writeByte(12)
        ..write(obj.bailleurName)
        ..writeByte(13)
        ..write(obj.bailleurEmail);
    }
    if (hasMontantPaye) {
      writer
        ..writeByte(14)
        ..write(obj.montantPaye);
    }
    if (hasVersements) {
      writer
        ..writeByte(15)
        ..write(Map<String, double>.from(obj.versementsSupplementaires));
    }
  }
}
