import 'package:hive_ce/hive.dart';
import 'package:uuid/uuid.dart';

/// Type de logement.
enum LogementType {
  appartement,
  maison,
  studio,
  autre;

  String get label {
    switch (this) {
      case LogementType.appartement:
        return 'Appartement';
      case LogementType.maison:
        return 'Maison';
      case LogementType.studio:
        return 'Studio';
      case LogementType.autre:
        return 'Autre';
    }
  }

  static LogementType fromString(String value) {
    return LogementType.values.firstWhere(
      (t) => t.name == value,
      orElse: () => LogementType.autre,
    );
  }
}

/// Un bien immobilier géré par le propriétaire.
class Logement {
  final String id;
  String libelle;
  String adresse;
  String codePostal;
  String ville;
  LogementType type;
  double surface;
  int nbPieces;
  double loyerHC;
  double charges;
  List<String> equipements;
  String notes;
  final DateTime createdAt;
  DateTime updatedAt;

  Logement({
    required this.id,
    required this.libelle,
    required this.adresse,
    required this.codePostal,
    required this.ville,
    required this.type,
    required this.surface,
    required this.nbPieces,
    required this.loyerHC,
    required this.charges,
    required this.equipements,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Logement.create({
    required String libelle,
    required String adresse,
    required String codePostal,
    required String ville,
    required LogementType type,
    required double surface,
    required int nbPieces,
    required double loyerHC,
    required double charges,
    List<String> equipements = const [],
    String notes = '',
  }) {
    final now = DateTime.now().toUtc();
    return Logement(
      id: const Uuid().v4(),
      libelle: libelle.trim(),
      adresse: adresse.trim(),
      codePostal: codePostal.trim(),
      ville: ville.trim(),
      type: type,
      surface: surface,
      nbPieces: nbPieces,
      loyerHC: loyerHC,
      charges: charges,
      equipements: List<String>.from(equipements),
      notes: notes.trim(),
      createdAt: now,
      updatedAt: now,
    );
  }

  double get loyerTTC => loyerHC + charges;

  String get adresseComplete => '$adresse, $codePostal $ville';
}

class LogementAdapter extends TypeAdapter<Logement> {
  @override
  final int typeId = 2;

  @override
  Logement read(BinaryReader reader) {
    final numFields = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < numFields; i++) reader.readByte(): reader.read(),
    };
    return Logement(
      id: fields[0] as String,
      libelle: fields[1] as String,
      adresse: fields[2] as String,
      codePostal: fields[3] as String,
      ville: fields[4] as String,
      type: LogementType.fromString(fields[5] as String),
      surface: fields[6] as double,
      nbPieces: fields[7] as int,
      loyerHC: fields[8] as double,
      charges: fields[9] as double,
      equipements: (fields[10] as List).cast<String>(),
      notes: fields[11] as String,
      createdAt: DateTime.parse(fields[12] as String),
      updatedAt: DateTime.parse(fields[13] as String),
    );
  }

  @override
  void write(BinaryWriter writer, Logement obj) {
    writer
      ..writeByte(14)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.libelle)
      ..writeByte(2)
      ..write(obj.adresse)
      ..writeByte(3)
      ..write(obj.codePostal)
      ..writeByte(4)
      ..write(obj.ville)
      ..writeByte(5)
      ..write(obj.type.name)
      ..writeByte(6)
      ..write(obj.surface)
      ..writeByte(7)
      ..write(obj.nbPieces)
      ..writeByte(8)
      ..write(obj.loyerHC)
      ..writeByte(9)
      ..write(obj.charges)
      ..writeByte(10)
      ..write(obj.equipements)
      ..writeByte(11)
      ..write(obj.notes)
      ..writeByte(12)
      ..write(obj.createdAt.toIso8601String())
      ..writeByte(13)
      ..write(obj.updatedAt.toIso8601String());
  }
}
