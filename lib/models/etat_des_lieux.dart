import 'package:hive_ce/hive.dart';
import 'package:uuid/uuid.dart';

import '../core/crypto/hash_service.dart';
import 'piece.dart';

enum EtatDesLieuxType {
  entree,
  sortie;

  String get label {
    switch (this) {
      case EtatDesLieuxType.entree:
        return 'Entrée';
      case EtatDesLieuxType.sortie:
        return 'Sortie';
    }
  }

  static EtatDesLieuxType fromString(String value) {
    return EtatDesLieuxType.values.firstWhere(
      (t) => t.name == value,
      orElse: () => EtatDesLieuxType.entree,
    );
  }
}

enum EtatDesLieuxStatus {
  brouillon,
  enAttenteSignatureLocataire,
  finalise;

  String get label {
    switch (this) {
      case EtatDesLieuxStatus.brouillon:
        return 'Brouillon';
      case EtatDesLieuxStatus.enAttenteSignatureLocataire:
        return 'Attente locataire';
      case EtatDesLieuxStatus.finalise:
        return 'Finalisé';
    }
  }

  static EtatDesLieuxStatus fromString(String value) {
    return EtatDesLieuxStatus.values.firstWhere(
      (s) => s.name == value,
      orElse: () => EtatDesLieuxStatus.brouillon,
    );
  }
}

/// Un état des lieux (entrée ou sortie).
///
/// Cycle de vie :
/// - `brouillon` : édition libre.
/// - `enAttenteSignatureLocataire` : le propriétaire a signé et généré un
///   code temporaire. Seule la signature du locataire fait avancer le statut.
/// - `finalise` : document signé par les deux parties. **Immutable.**
class EtatDesLieux {
  final String id;
  EtatDesLieuxType type;
  String logementId;
  String locataireId;
  DateTime date;
  EtatDesLieuxStatus status;
  List<Piece> pieces;
  String? proprietaireSignaturePng; // base64 du PNG
  DateTime? proprietaireSignatureAt;
  String? locataireCode; // code à 6 caractères
  DateTime? locataireSignatureAt;
  String? integrityHash;
  String notes;
  final DateTime createdAt;
  DateTime updatedAt;

  EtatDesLieux({
    required this.id,
    required this.type,
    required this.logementId,
    required this.locataireId,
    required this.date,
    required this.status,
    required this.pieces,
    required this.proprietaireSignaturePng,
    required this.proprietaireSignatureAt,
    required this.locataireCode,
    required this.locataireSignatureAt,
    required this.integrityHash,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory EtatDesLieux.create({
    required EtatDesLieuxType type,
    required String logementId,
    required String locataireId,
    required DateTime date,
    List<Piece>? pieces,
    String notes = '',
  }) {
    final now = DateTime.now().toUtc();
    return EtatDesLieux(
      id: const Uuid().v4(),
      type: type,
      logementId: logementId,
      locataireId: locataireId,
      date: date,
      status: EtatDesLieuxStatus.brouillon,
      pieces: pieces ?? <Piece>[],
      proprietaireSignaturePng: null,
      proprietaireSignatureAt: null,
      locataireCode: null,
      locataireSignatureAt: null,
      integrityHash: null,
      notes: notes.trim(),
      createdAt: now,
      updatedAt: now,
    );
  }

  bool get isFinalized => status == EtatDesLieuxStatus.finalise;
  bool get isDraft => status == EtatDesLieuxStatus.brouillon;
  bool get isPendingTenantSignature =>
      status == EtatDesLieuxStatus.enAttenteSignatureLocataire;

  /// Calcule le hash d'intégrité du document entier.
  ///
  /// Le hash inclut toutes les métadonnées, les pièces, les éléments,
  /// les signatures. Toute modification ultérieure invaliderait le hash.
  String computeIntegrityHash() {
    final piecesCanonical = pieces.map((p) => p.canonicalForHash).join('||');
    final payload = [
      id,
      type.name,
      logementId,
      locataireId,
      date.toUtc().toIso8601String(),
      piecesCanonical,
      proprietaireSignaturePng ?? '',
      proprietaireSignatureAt?.toUtc().toIso8601String() ?? '',
      locataireCode ?? '',
      locataireSignatureAt?.toUtc().toIso8601String() ?? '',
      notes.trim(),
      createdAt.toUtc().toIso8601String(),
    ].join('|::|');
    return HashService.sha256Hex(payload);
  }

  bool verifyIntegrity() {
    if (integrityHash == null) return false;
    return computeIntegrityHash() == integrityHash;
  }

  String get titre {
    final formattedDate =
        '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    return 'EDL ${type.label} — $formattedDate';
  }
}

class EtatDesLieuxAdapter extends TypeAdapter<EtatDesLieux> {
  @override
  final int typeId = 5;

  @override
  EtatDesLieux read(BinaryReader reader) {
    final numFields = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < numFields; i++) reader.readByte(): reader.read(),
    };
    return EtatDesLieux(
      id: fields[0] as String,
      type: EtatDesLieuxType.fromString(fields[1] as String),
      logementId: fields[2] as String,
      locataireId: fields[3] as String,
      date: DateTime.parse(fields[4] as String),
      status: EtatDesLieuxStatus.fromString(fields[5] as String),
      pieces: (fields[6] as List).cast<Piece>(),
      proprietaireSignaturePng: fields[7] as String?,
      proprietaireSignatureAt: fields[8] == null
          ? null
          : DateTime.parse(fields[8] as String),
      locataireCode: fields[9] as String?,
      locataireSignatureAt: fields[10] == null
          ? null
          : DateTime.parse(fields[10] as String),
      integrityHash: fields[11] as String?,
      notes: fields[12] as String,
      createdAt: DateTime.parse(fields[13] as String),
      updatedAt: DateTime.parse(fields[14] as String),
    );
  }

  @override
  void write(BinaryWriter writer, EtatDesLieux obj) {
    writer
      ..writeByte(15)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.type.name)
      ..writeByte(2)
      ..write(obj.logementId)
      ..writeByte(3)
      ..write(obj.locataireId)
      ..writeByte(4)
      ..write(obj.date.toIso8601String())
      ..writeByte(5)
      ..write(obj.status.name)
      ..writeByte(6)
      ..write(obj.pieces)
      ..writeByte(7)
      ..write(obj.proprietaireSignaturePng)
      ..writeByte(8)
      ..write(obj.proprietaireSignatureAt?.toIso8601String())
      ..writeByte(9)
      ..write(obj.locataireCode)
      ..writeByte(10)
      ..write(obj.locataireSignatureAt?.toIso8601String())
      ..writeByte(11)
      ..write(obj.integrityHash)
      ..writeByte(12)
      ..write(obj.notes)
      ..writeByte(13)
      ..write(obj.createdAt.toIso8601String())
      ..writeByte(14)
      ..write(obj.updatedAt.toIso8601String());
  }
}
