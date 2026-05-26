import 'package:hive_ce/hive.dart';
import 'package:uuid/uuid.dart';

import '../core/crypto/hash_service.dart';

/// Catégories de dépenses par défaut. L'utilisateur peut en ajouter d'autres
/// via la box `custom_expense_categories_box`.
class ExpenseCategories {
  static const String reparations = 'Réparations';
  static const String taxeFonciere = 'Taxe foncière';
  static const String assurance = 'Assurance';
  static const String charges = 'Charges';
  static const String entretien = 'Entretien';
  static const String honoraires = 'Honoraires';
  static const String credit = 'Crédit immobilier';
  static const String autre = 'Autre';

  static const List<String> defaults = [
    reparations,
    taxeFonciere,
    assurance,
    charges,
    entretien,
    honoraires,
    autre,
  ];
}

/// Dépense rattachée à un logement.
///
/// Les justificatifs (PDF, photos) sont stockés sous forme de chemins
/// relatifs au répertoire `<documents>/expense_justifs/<id>/`.
class Depense {
  final String id;
  final String logementId;
  String categorie;
  String libelle;
  double montant;
  DateTime date;
  String notes;
  List<String> justificatifs;
  final DateTime createdAt;
  String? integrityHash;

  Depense({
    required this.id,
    required this.logementId,
    required this.categorie,
    required this.libelle,
    required this.montant,
    required this.date,
    required this.notes,
    required this.justificatifs,
    required this.createdAt,
    this.integrityHash,
  });

  factory Depense.create({
    required String logementId,
    required String categorie,
    required String libelle,
    required double montant,
    required DateTime date,
    String notes = '',
    List<String> justificatifs = const [],
  }) {
    final now = DateTime.now().toUtc();
    final d = Depense(
      id: const Uuid().v4(),
      logementId: logementId,
      categorie: categorie.trim(),
      libelle: libelle.trim(),
      montant: montant,
      date: date,
      notes: notes.trim(),
      justificatifs: List<String>.from(justificatifs),
      createdAt: now,
    );
    d.integrityHash = d.computeIntegrityHash();
    return d;
  }

  String computeIntegrityHash() {
    final payload = [
      id,
      logementId,
      categorie,
      libelle,
      montant.toStringAsFixed(2),
      date.toUtc().toIso8601String(),
      notes,
      createdAt.toUtc().toIso8601String(),
    ].join('|::|');
    return HashService.sha256Hex(payload);
  }
}

class DepenseAdapter extends TypeAdapter<Depense> {
  @override
  final int typeId = 14;

  @override
  Depense read(BinaryReader reader) {
    final numFields = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < numFields; i++) reader.readByte(): reader.read(),
    };
    return Depense(
      id: fields[0] as String,
      logementId: fields[1] as String,
      categorie: fields[2] as String,
      libelle: fields[3] as String,
      montant: fields[4] as double,
      date: DateTime.parse(fields[5] as String),
      notes: fields[6] as String,
      justificatifs: (fields[7] as List).cast<String>(),
      createdAt: DateTime.parse(fields[8] as String),
      integrityHash: fields[9] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, Depense obj) {
    writer.writeByte(10);
    writer
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.logementId)
      ..writeByte(2)
      ..write(obj.categorie)
      ..writeByte(3)
      ..write(obj.libelle)
      ..writeByte(4)
      ..write(obj.montant)
      ..writeByte(5)
      ..write(obj.date.toUtc().toIso8601String())
      ..writeByte(6)
      ..write(obj.notes)
      ..writeByte(7)
      ..write(obj.justificatifs)
      ..writeByte(8)
      ..write(obj.createdAt.toUtc().toIso8601String())
      ..writeByte(9)
      ..write(obj.integrityHash);
  }
}
