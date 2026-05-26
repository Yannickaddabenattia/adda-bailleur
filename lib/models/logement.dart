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

/// Statut fiscal d'un logement (revenus fonciers).
/// Phase 1 : seul `locationNue` est pleinement supporté.
enum StatutFiscal {
  locationNue,
  lmnp,
  sci,
  autre;

  String get label {
    switch (this) {
      case StatutFiscal.locationNue:
        return 'Location nue';
      case StatutFiscal.lmnp:
        return 'LMNP';
      case StatutFiscal.sci:
        return 'SCI (à l\'IR)';
      case StatutFiscal.autre:
        return 'Autre / non déclaré';
    }
  }
}

/// Régime fiscal pour la location nue.
enum RegimeFiscal {
  reel,
  microFoncier;

  String get label {
    switch (this) {
      case RegimeFiscal.reel:
        return 'Réel';
      case RegimeFiscal.microFoncier:
        return 'Micro-foncier (abattement 30 %)';
    }
  }
}

/// Dispositif fiscal lié à un logement.
///
/// Deux familles :
/// - **Réduction d'impôt** (Pinel, Pinel+, Denormandie) : déduit directement
///   de l'IR additionnel foncier, plafonnée par le plafond des niches.
/// - **Abattement sur recettes** (Borloo Ancien intermédiaire/social/très
///   social) : réduit les recettes brutes du logement dans le calcul foncier
///   réel. Incompatible avec le micro-foncier.
enum DispositifFiscal {
  aucun,
  pinel,
  pinelPlus,
  denormandie,
  borlooAncienIntermediaire,
  borlooAncienSocial,
  borlooAncienTresSocial;

  String get label {
    switch (this) {
      case DispositifFiscal.aucun:
        return 'Aucun';
      case DispositifFiscal.pinel:
        return 'Pinel';
      case DispositifFiscal.pinelPlus:
        return 'Pinel+';
      case DispositifFiscal.denormandie:
        return 'Denormandie';
      case DispositifFiscal.borlooAncienIntermediaire:
        return 'Borloo Ancien intermédiaire (30 %)';
      case DispositifFiscal.borlooAncienSocial:
        return 'Borloo Ancien social (60 %)';
      case DispositifFiscal.borlooAncienTresSocial:
        return 'Borloo Ancien très social (70 %)';
    }
  }

  /// `true` si c'est un dispositif Borloo Ancien (abattement sur recettes).
  bool get isBorloo =>
      this == DispositifFiscal.borlooAncienIntermediaire ||
      this == DispositifFiscal.borlooAncienSocial ||
      this == DispositifFiscal.borlooAncienTresSocial;

  /// `true` si c'est un dispositif Pinel/Denormandie (réduction d'impôt).
  bool get isPinelDenormandie =>
      this == DispositifFiscal.pinel ||
      this == DispositifFiscal.pinelPlus ||
      this == DispositifFiscal.denormandie;

  /// Taux d'abattement Borloo sur les recettes brutes, 0 sinon.
  double get tauxAbattementBorloo {
    switch (this) {
      case DispositifFiscal.borlooAncienIntermediaire:
        return 0.30;
      case DispositifFiscal.borlooAncienSocial:
        return 0.60;
      case DispositifFiscal.borlooAncienTresSocial:
        return 0.70;
      default:
        return 0;
    }
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
  StatutFiscal statutFiscal;
  RegimeFiscal regimeFiscal;
  DispositifFiscal dispositif;
  DateTime? dateAcquisition;
  int dureeEngagementAnnees;
  double prixRevient;
  List<String> contratBailPaths;

  /// Référence vers la SCI (`SCI.id`) qui détient ce logement. `null` = bien
  /// détenu en direct par le propriétaire. Requis quand `statutFiscal ==
  /// StatutFiscal.sci`.
  String? sciId;

  /// Amortissement annuel du bâti, en €. Pertinent uniquement pour les
  /// logements détenus via une **SCI à l'IS** (déductible du bénéfice IS).
  /// L'utilisateur saisit le montant directement (libre).
  double amortissementAnnuel;

  /// Date de début d'application du dispositif fiscal sélectionné
  /// (Borloo / Pinel / Denormandie). Pour Borloo : requise. Pour
  /// Pinel/Denormandie : optionnelle (override la fenêtre auto-calculée).
  DateTime? dateDebutDispositif;

  /// Date de fin d'application du dispositif fiscal. Au-delà, le dispositif
  /// n'est plus pris en compte dans le calcul. Optionnelle dans le même
  /// esprit que [dateDebutDispositif].
  DateTime? dateFinDispositif;

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
    this.statutFiscal = StatutFiscal.locationNue,
    this.regimeFiscal = RegimeFiscal.reel,
    this.dispositif = DispositifFiscal.aucun,
    this.dateAcquisition,
    this.dureeEngagementAnnees = 9,
    this.prixRevient = 0,
    List<String>? contratBailPaths,
    this.sciId,
    this.amortissementAnnuel = 0,
    this.dateDebutDispositif,
    this.dateFinDispositif,
  }) : contratBailPaths = contratBailPaths ?? <String>[];

  /// `true` si le dispositif fiscal du logement est en vigueur pour [year]
  /// (entre [dateDebutDispositif] et [dateFinDispositif] inclus). Quand
  /// les dates ne sont pas renseignées :
  /// - Pour Borloo : retourne `false` (les dates sont obligatoires).
  /// - Pour Pinel/Denormandie : retourne `true` (la fenêtre est gérée par
  ///   `dateAcquisition` + `dureeEngagementAnnees` côté FiscaliteService).
  /// - Pour `aucun` : retourne `false`.
  bool dispositifActifPour(int year) {
    if (dispositif == DispositifFiscal.aucun) return false;
    if (dispositif.isBorloo) {
      if (dateDebutDispositif == null || dateFinDispositif == null) {
        return false;
      }
      return year >= dateDebutDispositif!.year &&
          year <= dateFinDispositif!.year;
    }
    // Pinel / Denormandie : si l'utilisateur a renseigné les dates, on les
    // respecte ; sinon on fait confiance à la fenêtre par défaut (acquisition
    // + durée d'engagement).
    if (dateDebutDispositif != null && year < dateDebutDispositif!.year) {
      return false;
    }
    if (dateFinDispositif != null && year > dateFinDispositif!.year) {
      return false;
    }
    return true;
  }

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
    StatutFiscal statutFiscal = StatutFiscal.locationNue,
    RegimeFiscal regimeFiscal = RegimeFiscal.reel,
    DispositifFiscal dispositif = DispositifFiscal.aucun,
    DateTime? dateAcquisition,
    int dureeEngagementAnnees = 9,
    double prixRevient = 0,
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
      statutFiscal: statutFiscal,
      regimeFiscal: regimeFiscal,
      dispositif: dispositif,
      dateAcquisition: dateAcquisition,
      dureeEngagementAnnees: dureeEngagementAnnees,
      prixRevient: prixRevient,
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
      statutFiscal: StatutFiscal.values.firstWhere(
        (s) => s.name == (fields[14] as String?),
        orElse: () => StatutFiscal.locationNue,
      ),
      regimeFiscal: RegimeFiscal.values.firstWhere(
        (r) => r.name == (fields[15] as String?),
        orElse: () => RegimeFiscal.reel,
      ),
      dispositif: DispositifFiscal.values.firstWhere(
        (d) => d.name == (fields[16] as String?),
        orElse: () => DispositifFiscal.aucun,
      ),
      dateAcquisition: fields[17] == null
          ? null
          : DateTime.parse(fields[17] as String),
      dureeEngagementAnnees: (fields[18] as int?) ?? 9,
      prixRevient: (fields[19] as num?)?.toDouble() ?? 0,
      contratBailPaths: (fields[20] as List?)?.cast<String>() ?? <String>[],
      sciId: fields[21] as String?,
      amortissementAnnuel: (fields[22] as num?)?.toDouble() ?? 0,
      dateDebutDispositif: fields[23] == null
          ? null
          : DateTime.parse(fields[23] as String),
      dateFinDispositif: fields[24] == null
          ? null
          : DateTime.parse(fields[24] as String),
    );
  }

  @override
  void write(BinaryWriter writer, Logement obj) {
    writer
      ..writeByte(25)
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
      ..write(obj.updatedAt.toIso8601String())
      ..writeByte(14)
      ..write(obj.statutFiscal.name)
      ..writeByte(15)
      ..write(obj.regimeFiscal.name)
      ..writeByte(16)
      ..write(obj.dispositif.name)
      ..writeByte(17)
      ..write(obj.dateAcquisition?.toIso8601String())
      ..writeByte(18)
      ..write(obj.dureeEngagementAnnees)
      ..writeByte(19)
      ..write(obj.prixRevient)
      ..writeByte(20)
      ..write(obj.contratBailPaths)
      ..writeByte(21)
      ..write(obj.sciId)
      ..writeByte(22)
      ..write(obj.amortissementAnnuel)
      ..writeByte(23)
      ..write(obj.dateDebutDispositif?.toIso8601String())
      ..writeByte(24)
      ..write(obj.dateFinDispositif?.toIso8601String());
  }
}
