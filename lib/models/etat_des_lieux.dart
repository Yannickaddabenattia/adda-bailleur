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
  /// Code à 6 caractères. Conservé pour compatibilité avec les anciens EDL ;
  /// le flux courant utilise une signature manuscrite du locataire.
  String? locataireCode;
  String? locataireSignaturePng; // base64 du PNG, null tant que non signé
  DateTime? locataireSignatureAt;
  String? integrityHash;
  String notes;
  // Champs ajoutés en v3.3 — métadonnées EDL conformes ALUR.
  /// Adresse postale complète du bailleur (peut différer du logement loué).
  String? bailleurAdresse;
  /// Nombre de clés / badges remis au locataire à l'entrée (ou rendus à la sortie).
  int? nombreCles;
  String? releveCompteurGaz;
  String? releveCompteurEauChaude;
  String? releveCompteurEauFroide;
  String? releveCompteurElecJour;
  String? releveCompteurElecNuit;
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
    this.locataireSignaturePng,
    required this.locataireSignatureAt,
    required this.integrityHash,
    required this.notes,
    this.bailleurAdresse,
    this.nombreCles,
    this.releveCompteurGaz,
    this.releveCompteurEauChaude,
    this.releveCompteurEauFroide,
    this.releveCompteurElecJour,
    this.releveCompteurElecNuit,
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
    String? bailleurAdresse,
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
      locataireSignaturePng: null,
      locataireSignatureAt: null,
      integrityHash: null,
      notes: notes.trim(),
      bailleurAdresse: bailleurAdresse?.trim().isEmpty ?? true
          ? null
          : bailleurAdresse!.trim(),
      nombreCles: null,
      releveCompteurGaz: null,
      releveCompteurEauChaude: null,
      releveCompteurEauFroide: null,
      releveCompteurElecJour: null,
      releveCompteurElecNuit: null,
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
  ///
  /// Note compat : les champs ajoutés en v3.3 ne sont inclus que s'ils sont
  /// renseignés, pour que les EDL pré-v3.3 (où ces champs sont null) gardent
  /// un hash valide. Si l'attaquant ajoute une valeur après finalisation, le
  /// recalcul l'inclut → la vérification échoue, ce qui est le comportement
  /// désiré.
  String computeIntegrityHash() {
    final piecesCanonical = pieces.map((p) => p.canonicalForHash).join('||');
    final parts = <String>[
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
    ];
    _appendV33Fields(parts);
    return HashService.sha256Hex(parts.join('|::|'));
  }

  bool verifyIntegrity() {
    if (integrityHash == null) return false;
    return computeIntegrityHash() == integrityHash;
  }

  /// Hash stable indépendant de la signature locataire (utilisé dans le mailto
  /// de "bon pour accord" envoyé par le locataire depuis son téléphone perso —
  /// il doit être reproductible à tout moment pour vérification).
  String computePreSignatureHash() {
    final piecesCanonical = pieces.map((p) => p.canonicalForHash).join('||');
    final parts = <String>[
      id,
      type.name,
      logementId,
      locataireId,
      date.toUtc().toIso8601String(),
      piecesCanonical,
      proprietaireSignaturePng ?? '',
      proprietaireSignatureAt?.toUtc().toIso8601String() ?? '',
      notes.trim(),
      createdAt.toUtc().toIso8601String(),
    ];
    _appendV33Fields(parts);
    return HashService.sha256Hex(parts.join('|::|'));
  }

  void _appendV33Fields(List<String> parts) {
    if (bailleurAdresse != null && bailleurAdresse!.trim().isNotEmpty) {
      parts.add('bailleurAdresse=${bailleurAdresse!.trim()}');
    }
    if (nombreCles != null) parts.add('nombreCles=$nombreCles');
    if (releveCompteurGaz != null && releveCompteurGaz!.trim().isNotEmpty) {
      parts.add('gaz=${releveCompteurGaz!.trim()}');
    }
    if (releveCompteurEauChaude != null &&
        releveCompteurEauChaude!.trim().isNotEmpty) {
      parts.add('eauChaude=${releveCompteurEauChaude!.trim()}');
    }
    if (releveCompteurEauFroide != null &&
        releveCompteurEauFroide!.trim().isNotEmpty) {
      parts.add('eauFroide=${releveCompteurEauFroide!.trim()}');
    }
    if (releveCompteurElecJour != null &&
        releveCompteurElecJour!.trim().isNotEmpty) {
      parts.add('elecJour=${releveCompteurElecJour!.trim()}');
    }
    if (releveCompteurElecNuit != null &&
        releveCompteurElecNuit!.trim().isNotEmpty) {
      parts.add('elecNuit=${releveCompteurElecNuit!.trim()}');
    }
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
      locataireSignaturePng: fields[15] as String?,
      bailleurAdresse: fields[16] as String?,
      nombreCles: fields[17] as int?,
      releveCompteurGaz: fields[18] as String?,
      releveCompteurEauChaude: fields[19] as String?,
      releveCompteurEauFroide: fields[20] as String?,
      releveCompteurElecJour: fields[21] as String?,
      releveCompteurElecNuit: fields[22] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, EtatDesLieux obj) {
    writer
      ..writeByte(23)
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
      ..write(obj.updatedAt.toIso8601String())
      ..writeByte(15)
      ..write(obj.locataireSignaturePng)
      ..writeByte(16)
      ..write(obj.bailleurAdresse)
      ..writeByte(17)
      ..write(obj.nombreCles)
      ..writeByte(18)
      ..write(obj.releveCompteurGaz)
      ..writeByte(19)
      ..write(obj.releveCompteurEauChaude)
      ..writeByte(20)
      ..write(obj.releveCompteurEauFroide)
      ..writeByte(21)
      ..write(obj.releveCompteurElecJour)
      ..writeByte(22)
      ..write(obj.releveCompteurElecNuit);
  }
}
