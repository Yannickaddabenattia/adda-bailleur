import 'package:hive_ce/hive.dart';
import 'package:uuid/uuid.dart';

/// Avenant à un contrat de bail existant. Modifie ponctuellement le loyer,
/// la durée, ou ajoute des clauses sans rompre le contrat initial.
///
/// Référence le `ContratBail.id` parent. Chaque avenant a sa propre date de
/// signature, son hash d'intégrité, et son PDF.
class Avenant {
  final String id;
  final String contratBailId;

  /// Numéro d'ordre (1, 2, 3…) attribué à la création.
  int numero;

  /// Date d'effet de l'avenant (peut être différente de la date de signature).
  DateTime dateEffet;

  /// Description structurée des modifications. Texte libre côté UI ; le PDF
  /// affichera les sections clairement.
  String objet;
  String description;

  /// Nouvelles valeurs si l'avenant modifie un champ du bail. Null = pas
  /// de changement de ce champ.
  double? nouveauLoyerHC;
  double? nouvellesCharges;
  int? nouvelleDureeMois;
  DateTime? nouvelleDateFin;

  /// Signatures.
  String? signatureBailleurPng;
  DateTime? signatureBailleurAt;
  Map<String, String> signaturesLocatairesPng;
  Map<String, String> signaturesLocatairesAt;

  String? integrityHash;
  String? pdfPath;

  final DateTime createdAt;
  DateTime updatedAt;

  Avenant({
    required this.id,
    required this.contratBailId,
    required this.numero,
    required this.dateEffet,
    required this.objet,
    required this.description,
    this.nouveauLoyerHC,
    this.nouvellesCharges,
    this.nouvelleDureeMois,
    this.nouvelleDateFin,
    this.signatureBailleurPng,
    this.signatureBailleurAt,
    Map<String, String>? signaturesLocatairesPng,
    Map<String, String>? signaturesLocatairesAt,
    this.integrityHash,
    this.pdfPath,
    required this.createdAt,
    required this.updatedAt,
  })  : signaturesLocatairesPng = signaturesLocatairesPng ?? {},
        signaturesLocatairesAt = signaturesLocatairesAt ?? {};

  factory Avenant.create({
    required String contratBailId,
    required int numero,
    required DateTime dateEffet,
    required String objet,
    String description = '',
  }) {
    final now = DateTime.now().toUtc();
    return Avenant(
      id: const Uuid().v4(),
      contratBailId: contratBailId,
      numero: numero,
      dateEffet: dateEffet,
      objet: objet.trim(),
      description: description.trim(),
      createdAt: now,
      updatedAt: now,
    );
  }
}

class AvenantAdapter extends TypeAdapter<Avenant> {
  @override
  final int typeId = 20;

  @override
  Avenant read(BinaryReader reader) {
    final n = reader.readByte();
    final f = <int, dynamic>{
      for (var i = 0; i < n; i++) reader.readByte(): reader.read(),
    };
    final sigPngRaw = f[12] as Map?;
    final sigPng = <String, String>{};
    sigPngRaw?.forEach((k, v) {
      if (k is String && v is String) sigPng[k] = v;
    });
    final sigAtRaw = f[13] as Map?;
    final sigAt = <String, String>{};
    sigAtRaw?.forEach((k, v) {
      if (k is String && v is String) sigAt[k] = v;
    });
    return Avenant(
      id: f[0] as String,
      contratBailId: f[1] as String,
      numero: (f[2] as num).toInt(),
      dateEffet: DateTime.parse(f[3] as String),
      objet: f[4] as String,
      description: f[5] as String,
      nouveauLoyerHC: (f[6] as num?)?.toDouble(),
      nouvellesCharges: (f[7] as num?)?.toDouble(),
      nouvelleDureeMois: (f[8] as num?)?.toInt(),
      nouvelleDateFin: f[9] is String
          ? DateTime.parse(f[9] as String)
          : null,
      signatureBailleurPng: f[10] as String?,
      signatureBailleurAt: f[11] is String
          ? DateTime.parse(f[11] as String)
          : null,
      signaturesLocatairesPng: sigPng,
      signaturesLocatairesAt: sigAt,
      integrityHash: f[14] as String?,
      pdfPath: f[15] as String?,
      createdAt: DateTime.parse(f[16] as String),
      updatedAt: DateTime.parse(f[17] as String),
    );
  }

  @override
  void write(BinaryWriter writer, Avenant obj) {
    writer
      ..writeByte(18)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.contratBailId)
      ..writeByte(2)
      ..write(obj.numero)
      ..writeByte(3)
      ..write(obj.dateEffet.toIso8601String())
      ..writeByte(4)
      ..write(obj.objet)
      ..writeByte(5)
      ..write(obj.description)
      ..writeByte(6)
      ..write(obj.nouveauLoyerHC)
      ..writeByte(7)
      ..write(obj.nouvellesCharges)
      ..writeByte(8)
      ..write(obj.nouvelleDureeMois)
      ..writeByte(9)
      ..write(obj.nouvelleDateFin?.toIso8601String())
      ..writeByte(10)
      ..write(obj.signatureBailleurPng)
      ..writeByte(11)
      ..write(obj.signatureBailleurAt?.toIso8601String())
      ..writeByte(12)
      ..write(obj.signaturesLocatairesPng)
      ..writeByte(13)
      ..write(obj.signaturesLocatairesAt)
      ..writeByte(14)
      ..write(obj.integrityHash)
      ..writeByte(15)
      ..write(obj.pdfPath)
      ..writeByte(16)
      ..write(obj.createdAt.toIso8601String())
      ..writeByte(17)
      ..write(obj.updatedAt.toIso8601String());
  }
}
