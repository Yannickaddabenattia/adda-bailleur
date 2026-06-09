import 'package:hive_ce/hive.dart';
import 'package:uuid/uuid.dart';

import 'clause.dart';
import 'contrat_bail.dart';

/// Template de contrat de bail prêt-à-l'emploi.
///
/// Deux sources possibles :
/// - **Templates système** ([isSystem] = true) : définis en const dans
///   `lib/data/bail_templates_system.dart`, livrés avec l'app, lecture seule.
/// - **Templates utilisateur** ([isSystem] = false) : créés par le bailleur,
///   stockés dans la box Hive chiffrée `bail_templates_box`.
///
/// Un template encapsule : un [BailType], les valeurs par défaut (durée, dépôt,
/// préavis…), une liste d'IDs de clauses pré-cochées issues du catalogue
/// standard, et une liste de clauses personnalisées embarquées.
///
/// L'application d'un template à un nouveau bail se fait via
/// [ContratBail.fromTemplate] (factory dans `contrat_bail.dart`) : le bail
/// résultant est ensuite indépendant — modifier le template n'affecte pas les
/// bails existants.
class BailTemplate {
  /// `BAIL_NU_RP_3A` (système) ou UUID (utilisateur).
  final String id;

  String nom;
  String description;
  BailType typeBail;

  int dureeDefautMois;

  /// Dépôt par défaut, exprimé en multiplicateur du loyer HC
  /// (ex : 1.0 = 1 mois, 2.0 = 2 mois). Ignoré si [depotInterdit] = true.
  double depotMultiplicateurLoyer;

  /// Si `true` : le dépôt de garantie est interdit (cas du bail mobilité,
  /// art. 25-15 loi 89-462). Le montant sera forcé à 0.
  bool depotInterdit;

  int preavisBailleurMois;
  int preavisLocataireMois;
  bool renouvellementTacite;

  /// Pour le bail mobilité : le motif (justificatif) est requis.
  bool justificatifMobiliteRequis;

  /// IDs de clauses du catalogue standard (`cat_*` / `cat_v2_*`) à pré-cocher.
  List<String> clausesPreCochees;

  /// Clauses personnalisées embarquées dans le template (jardin, copro…).
  List<Clause> clausesPersoIncluses;

  /// Équipements meublé par défaut (clés du décret 2015-981). Optionnel.
  Map<String, bool>? equipementsMeubleDefauts;

  /// Note d'introduction du PDF (optionnel) : rappel légal, mention spécifique.
  String? noteIntroPdf;

  /// `true` = template système (lecture seule, source = code Dart).
  /// `false` = template utilisateur (stocké en base, éditable).
  final bool isSystem;

  /// Si l'utilisateur a dupliqué un template système, on garde la trace.
  String? sourceSystemId;

  final DateTime? dateCreation;
  DateTime? dateModification;

  /// Compteur d'utilisations (incrémenté à chaque génération de bail).
  /// Pour les templates système, ce compteur est ignoré (toujours 0 en base).
  int nbUtilisations;

  BailTemplate({
    required this.id,
    required this.nom,
    required this.description,
    required this.typeBail,
    required this.dureeDefautMois,
    required this.depotMultiplicateurLoyer,
    this.depotInterdit = false,
    required this.preavisBailleurMois,
    required this.preavisLocataireMois,
    required this.renouvellementTacite,
    this.justificatifMobiliteRequis = false,
    this.clausesPreCochees = const [],
    this.clausesPersoIncluses = const [],
    this.equipementsMeubleDefauts,
    this.noteIntroPdf,
    this.isSystem = false,
    this.sourceSystemId,
    this.dateCreation,
    this.dateModification,
    this.nbUtilisations = 0,
  });

  /// Crée un template utilisateur (UUID + timestamps).
  factory BailTemplate.userTemplate({
    required String nom,
    required String description,
    required BailType typeBail,
    required int dureeDefautMois,
    required double depotMultiplicateurLoyer,
    bool depotInterdit = false,
    required int preavisBailleurMois,
    required int preavisLocataireMois,
    required bool renouvellementTacite,
    bool justificatifMobiliteRequis = false,
    List<String> clausesPreCochees = const [],
    List<Clause> clausesPersoIncluses = const [],
    Map<String, bool>? equipementsMeubleDefauts,
    String? noteIntroPdf,
    String? sourceSystemId,
  }) {
    final now = DateTime.now().toUtc();
    return BailTemplate(
      id: const Uuid().v4(),
      nom: nom.trim(),
      description: description.trim(),
      typeBail: typeBail,
      dureeDefautMois: dureeDefautMois,
      depotMultiplicateurLoyer: depotMultiplicateurLoyer,
      depotInterdit: depotInterdit,
      preavisBailleurMois: preavisBailleurMois,
      preavisLocataireMois: preavisLocataireMois,
      renouvellementTacite: renouvellementTacite,
      justificatifMobiliteRequis: justificatifMobiliteRequis,
      clausesPreCochees: List.of(clausesPreCochees),
      clausesPersoIncluses: clausesPersoIncluses.map((c) => c.copy()).toList(),
      equipementsMeubleDefauts: equipementsMeubleDefauts == null
          ? null
          : Map<String, bool>.from(equipementsMeubleDefauts),
      noteIntroPdf: noteIntroPdf,
      isSystem: false,
      sourceSystemId: sourceSystemId,
      dateCreation: now,
      dateModification: now,
      nbUtilisations: 0,
    );
  }

  BailTemplate copy() => BailTemplate(
        id: id,
        nom: nom,
        description: description,
        typeBail: typeBail,
        dureeDefautMois: dureeDefautMois,
        depotMultiplicateurLoyer: depotMultiplicateurLoyer,
        depotInterdit: depotInterdit,
        preavisBailleurMois: preavisBailleurMois,
        preavisLocataireMois: preavisLocataireMois,
        renouvellementTacite: renouvellementTacite,
        justificatifMobiliteRequis: justificatifMobiliteRequis,
        clausesPreCochees: List.of(clausesPreCochees),
        clausesPersoIncluses:
            clausesPersoIncluses.map((c) => c.copy()).toList(),
        equipementsMeubleDefauts: equipementsMeubleDefauts == null
            ? null
            : Map<String, bool>.from(equipementsMeubleDefauts!),
        noteIntroPdf: noteIntroPdf,
        isSystem: isSystem,
        sourceSystemId: sourceSystemId,
        dateCreation: dateCreation,
        dateModification: dateModification,
        nbUtilisations: nbUtilisations,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'nom': nom,
        'description': description,
        'typeBail': typeBail.name,
        'dureeDefautMois': dureeDefautMois,
        'depotMultiplicateurLoyer': depotMultiplicateurLoyer,
        'depotInterdit': depotInterdit,
        'preavisBailleurMois': preavisBailleurMois,
        'preavisLocataireMois': preavisLocataireMois,
        'renouvellementTacite': renouvellementTacite,
        'justificatifMobiliteRequis': justificatifMobiliteRequis,
        'clausesPreCochees': clausesPreCochees,
        'clausesPersoIncluses':
            clausesPersoIncluses.map((c) => c.toMap()).toList(),
        'equipementsMeubleDefauts': equipementsMeubleDefauts,
        'noteIntroPdf': noteIntroPdf,
        'isSystem': isSystem,
        'sourceSystemId': sourceSystemId,
        'dateCreation': dateCreation?.toIso8601String(),
        'dateModification': dateModification?.toIso8601String(),
        'nbUtilisations': nbUtilisations,
      };

  factory BailTemplate.fromMap(Map<String, dynamic> m) {
    final rawEquip = m['equipementsMeubleDefauts'] as Map?;
    Map<String, bool>? equip;
    if (rawEquip != null) {
      equip = <String, bool>{};
      rawEquip.forEach((k, v) {
        if (k is String && v is bool) equip![k] = v;
      });
    }
    return BailTemplate(
      id: m['id'] as String? ?? const Uuid().v4(),
      nom: (m['nom'] as String?) ?? '',
      description: (m['description'] as String?) ?? '',
      typeBail: BailType.values.firstWhere(
        (t) => t.name == (m['typeBail'] as String?),
        orElse: () => BailType.vide,
      ),
      dureeDefautMois: (m['dureeDefautMois'] as num?)?.toInt() ?? 36,
      depotMultiplicateurLoyer:
          (m['depotMultiplicateurLoyer'] as num?)?.toDouble() ?? 1.0,
      depotInterdit: (m['depotInterdit'] as bool?) ?? false,
      preavisBailleurMois: (m['preavisBailleurMois'] as num?)?.toInt() ?? 3,
      preavisLocataireMois: (m['preavisLocataireMois'] as num?)?.toInt() ?? 1,
      renouvellementTacite: (m['renouvellementTacite'] as bool?) ?? true,
      justificatifMobiliteRequis:
          (m['justificatifMobiliteRequis'] as bool?) ?? false,
      clausesPreCochees:
          (m['clausesPreCochees'] as List?)?.cast<String>() ?? <String>[],
      clausesPersoIncluses: (m['clausesPersoIncluses'] as List?)
              ?.map((e) => Clause.fromMap((e as Map).cast<String, dynamic>()))
              .toList() ??
          <Clause>[],
      equipementsMeubleDefauts: equip,
      noteIntroPdf: m['noteIntroPdf'] as String?,
      isSystem: (m['isSystem'] as bool?) ?? false,
      sourceSystemId: m['sourceSystemId'] as String?,
      dateCreation: m['dateCreation'] is String
          ? DateTime.parse(m['dateCreation'] as String)
          : null,
      dateModification: m['dateModification'] is String
          ? DateTime.parse(m['dateModification'] as String)
          : null,
      nbUtilisations: (m['nbUtilisations'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Adapter Hive manuel pour [BailTemplate]. typeId = 56.
class BailTemplateAdapter extends TypeAdapter<BailTemplate> {
  @override
  final int typeId = 56;

  @override
  BailTemplate read(BinaryReader reader) {
    final n = reader.readByte();
    final f = <int, dynamic>{
      for (var i = 0; i < n; i++) reader.readByte(): reader.read(),
    };
    final rawEquip = f[13] as Map?;
    Map<String, bool>? equip;
    if (rawEquip != null) {
      equip = <String, bool>{};
      rawEquip.forEach((k, v) {
        if (k is String && v is bool) equip![k] = v;
      });
    }
    return BailTemplate(
      id: f[0] as String,
      nom: (f[1] as String?) ?? '',
      description: (f[2] as String?) ?? '',
      typeBail: BailType.values.firstWhere(
        (t) => t.name == (f[3] as String?),
        orElse: () => BailType.vide,
      ),
      dureeDefautMois: (f[4] as num?)?.toInt() ?? 36,
      depotMultiplicateurLoyer: (f[5] as num?)?.toDouble() ?? 1.0,
      depotInterdit: (f[6] as bool?) ?? false,
      preavisBailleurMois: (f[7] as num?)?.toInt() ?? 3,
      preavisLocataireMois: (f[8] as num?)?.toInt() ?? 1,
      renouvellementTacite: (f[9] as bool?) ?? true,
      justificatifMobiliteRequis: (f[10] as bool?) ?? false,
      clausesPreCochees:
          (f[11] as List?)?.cast<String>() ?? <String>[],
      clausesPersoIncluses: (f[12] as List?)
              ?.map((e) => Clause.fromMap((e as Map).cast<String, dynamic>()))
              .toList() ??
          <Clause>[],
      equipementsMeubleDefauts: equip,
      noteIntroPdf: f[14] as String?,
      isSystem: (f[15] as bool?) ?? false,
      sourceSystemId: f[16] as String?,
      dateCreation: f[17] is String
          ? DateTime.parse(f[17] as String)
          : null,
      dateModification: f[18] is String
          ? DateTime.parse(f[18] as String)
          : null,
      nbUtilisations: (f[19] as num?)?.toInt() ?? 0,
    );
  }

  @override
  void write(BinaryWriter writer, BailTemplate obj) {
    writer
      ..writeByte(20)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.nom)
      ..writeByte(2)
      ..write(obj.description)
      ..writeByte(3)
      ..write(obj.typeBail.name)
      ..writeByte(4)
      ..write(obj.dureeDefautMois)
      ..writeByte(5)
      ..write(obj.depotMultiplicateurLoyer)
      ..writeByte(6)
      ..write(obj.depotInterdit)
      ..writeByte(7)
      ..write(obj.preavisBailleurMois)
      ..writeByte(8)
      ..write(obj.preavisLocataireMois)
      ..writeByte(9)
      ..write(obj.renouvellementTacite)
      ..writeByte(10)
      ..write(obj.justificatifMobiliteRequis)
      ..writeByte(11)
      ..write(obj.clausesPreCochees)
      ..writeByte(12)
      ..write(obj.clausesPersoIncluses.map((c) => c.toMap()).toList())
      ..writeByte(13)
      ..write(obj.equipementsMeubleDefauts)
      ..writeByte(14)
      ..write(obj.noteIntroPdf)
      ..writeByte(15)
      ..write(obj.isSystem)
      ..writeByte(16)
      ..write(obj.sourceSystemId)
      ..writeByte(17)
      ..write(obj.dateCreation?.toIso8601String())
      ..writeByte(18)
      ..write(obj.dateModification?.toIso8601String())
      ..writeByte(19)
      ..write(obj.nbUtilisations);
  }
}
