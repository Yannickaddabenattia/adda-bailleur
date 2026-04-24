import 'package:hive_ce/hive.dart';
import 'package:uuid/uuid.dart';

/// Un locataire géré par le propriétaire.
///
/// Note : il s'agit d'une **entité** dans la base du propriétaire, différente
/// du profil utilisateur de l'application (qui lui est figé).
/// Le propriétaire peut librement ajouter / modifier / supprimer ses locataires.
class Locataire {
  final String id;
  String firstName;
  String lastName;
  String email;
  String? phone;
  List<String> logementIds;
  DateTime? dateEntree;
  String notes;
  final DateTime createdAt;
  DateTime updatedAt;

  Locataire({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phone,
    required this.logementIds,
    required this.dateEntree,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Locataire.create({
    required String firstName,
    required String lastName,
    required String email,
    String? phone,
    List<String> logementIds = const [],
    DateTime? dateEntree,
    String notes = '',
  }) {
    final now = DateTime.now().toUtc();
    return Locataire(
      id: const Uuid().v4(),
      firstName: firstName.trim(),
      lastName: lastName.trim().toUpperCase(),
      email: email.trim().toLowerCase(),
      phone: phone?.trim().isEmpty ?? true ? null : phone!.trim(),
      logementIds: List<String>.from(logementIds),
      dateEntree: dateEntree,
      notes: notes.trim(),
      createdAt: now,
      updatedAt: now,
    );
  }

  String get fullName => '$firstName $lastName';
}

class LocataireAdapter extends TypeAdapter<Locataire> {
  @override
  final int typeId = 4;

  @override
  Locataire read(BinaryReader reader) {
    final numFields = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < numFields; i++) reader.readByte(): reader.read(),
    };
    return Locataire(
      id: fields[0] as String,
      firstName: fields[1] as String,
      lastName: fields[2] as String,
      email: fields[3] as String,
      phone: fields[4] as String?,
      logementIds: (fields[5] as List).cast<String>(),
      dateEntree: fields[6] == null ? null : DateTime.parse(fields[6] as String),
      notes: fields[7] as String,
      createdAt: DateTime.parse(fields[8] as String),
      updatedAt: DateTime.parse(fields[9] as String),
    );
  }

  @override
  void write(BinaryWriter writer, Locataire obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.firstName)
      ..writeByte(2)
      ..write(obj.lastName)
      ..writeByte(3)
      ..write(obj.email)
      ..writeByte(4)
      ..write(obj.phone)
      ..writeByte(5)
      ..write(obj.logementIds)
      ..writeByte(6)
      ..write(obj.dateEntree?.toIso8601String())
      ..writeByte(7)
      ..write(obj.notes)
      ..writeByte(8)
      ..write(obj.createdAt.toIso8601String())
      ..writeByte(9)
      ..write(obj.updatedAt.toIso8601String());
  }
}
