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
  bool isPrincipal;
  DateTime? dateSortie;
  String raisonSortie;
  double? loyerSortie;
  List<String> contratBailPaths;
  String? nouvelleAdresse;
  String? nouveauTelephone;
  String? nouvelEmail;
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
    this.isPrincipal = false,
    this.dateSortie,
    this.raisonSortie = '',
    this.loyerSortie,
    List<String>? contratBailPaths,
    this.nouvelleAdresse,
    this.nouveauTelephone,
    this.nouvelEmail,
    required this.createdAt,
    required this.updatedAt,
  }) : contratBailPaths = contratBailPaths ?? <String>[];

  factory Locataire.create({
    required String firstName,
    required String lastName,
    required String email,
    String? phone,
    List<String> logementIds = const [],
    DateTime? dateEntree,
    String notes = '',
    bool isPrincipal = false,
    DateTime? dateSortie,
    String raisonSortie = '',
    double? loyerSortie,
    String? nouvelleAdresse,
    String? nouveauTelephone,
    String? nouvelEmail,
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
      isPrincipal: isPrincipal,
      dateSortie: dateSortie,
      raisonSortie: raisonSortie.trim(),
      loyerSortie: loyerSortie,
      nouvelleAdresse: nouvelleAdresse?.trim().isEmpty ?? true
          ? null
          : nouvelleAdresse!.trim(),
      nouveauTelephone: nouveauTelephone?.trim().isEmpty ?? true
          ? null
          : nouveauTelephone!.trim(),
      nouvelEmail: nouvelEmail?.trim().isEmpty ?? true
          ? null
          : nouvelEmail!.trim().toLowerCase(),
      createdAt: now,
      updatedAt: now,
    );
  }

  String get fullName => '$firstName $lastName';

  bool get isArchived {
    final ds = dateSortie;
    if (ds == null) return false;
    return !ds.isAfter(DateTime.now());
  }

  bool get isFutur {
    if (isArchived) return false;
    final de = dateEntree;
    if (de == null) return false;
    return de.isAfter(DateTime.now());
  }
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
      isPrincipal: (fields[10] as bool?) ?? false,
      dateSortie: fields[11] == null ? null : DateTime.parse(fields[11] as String),
      raisonSortie: (fields[12] as String?) ?? '',
      loyerSortie: fields[13] as double?,
      contratBailPaths: _readContratPaths(fields[14]),
      nouvelleAdresse: fields[15] as String?,
      nouveauTelephone: fields[16] as String?,
      nouvelEmail: fields[17] as String?,
    );
  }

  static List<String> _readContratPaths(dynamic raw) {
    if (raw == null) return <String>[];
    if (raw is String) return raw.isEmpty ? <String>[] : <String>[raw];
    if (raw is List) return raw.cast<String>();
    return <String>[];
  }

  @override
  void write(BinaryWriter writer, Locataire obj) {
    writer
      ..writeByte(18)
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
      ..write(obj.updatedAt.toIso8601String())
      ..writeByte(10)
      ..write(obj.isPrincipal)
      ..writeByte(11)
      ..write(obj.dateSortie?.toIso8601String())
      ..writeByte(12)
      ..write(obj.raisonSortie)
      ..writeByte(13)
      ..write(obj.loyerSortie)
      ..writeByte(14)
      ..write(obj.contratBailPaths)
      ..writeByte(15)
      ..write(obj.nouvelleAdresse)
      ..writeByte(16)
      ..write(obj.nouveauTelephone)
      ..writeByte(17)
      ..write(obj.nouvelEmail);
  }
}
