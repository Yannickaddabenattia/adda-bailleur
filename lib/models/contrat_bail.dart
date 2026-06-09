import 'package:hive_ce/hive.dart';
import 'package:uuid/uuid.dart';

import 'bail_template.dart';
import 'clause.dart';
import 'garant.dart';

/// Type de bail couvert par l'application. Chaque type a ses propres durées
/// minimales, plafonds de dépôt et clauses spécifiques.
enum BailType {
  vide,
  meuble,
  colocation,
  saisonnier,
  mobilite;

  String get label {
    switch (this) {
      case BailType.vide:
        return 'Bail vide (location nue)';
      case BailType.meuble:
        return 'Bail meublé';
      case BailType.colocation:
        return 'Bail de colocation';
      case BailType.saisonnier:
        return 'Bail saisonnier';
      case BailType.mobilite:
        return 'Bail mobilité';
    }
  }

  /// Durée par défaut en mois (3 ans = 36, 1 an = 12, etc.).
  int get dureeDefautMois {
    switch (this) {
      case BailType.vide:
        return 36;
      case BailType.meuble:
        return 12;
      case BailType.colocation:
        return 36;
      case BailType.saisonnier:
        return 3;
      case BailType.mobilite:
        return 6;
    }
  }

  /// Plafond légal du dépôt de garantie, en nombre de mois de loyer HC.
  /// - Vide : 1 mois (loi n°89-462 du 6 juillet 1989, art. 22).
  /// - Meublé : 2 mois (art. 25-6).
  /// - Mobilité : dépôt de garantie interdit, 0 mois (loi ELAN, art. 25-12).
  /// - Colocation à bail unique : jusqu'à 2 mois si meublée (1 si nue) — on
  ///   retient le plafond le plus large faute de distinguer nu/meublé ici.
  /// - Saisonnier : hors loi de 1989 (dépôt libre), plafond indicatif.
  int get plafondDepotMois {
    switch (this) {
      case BailType.vide:
        return 1;
      case BailType.meuble:
        return 2;
      case BailType.colocation:
        return 2;
      case BailType.mobilite:
        return 0;
      case BailType.saisonnier:
        return 2;
    }
  }

  /// Préavis légal du bailleur (en mois).
  int get preavisBailleurMois {
    switch (this) {
      case BailType.vide:
        return 6;
      case BailType.colocation:
        return 6;
      case BailType.meuble:
        return 3;
      case BailType.mobilite:
        return 1;
      case BailType.saisonnier:
        return 0;
    }
  }

  /// Préavis légal du locataire (en mois). Zone tendue ou motif
  /// professionnel/médical : 1 mois (à gérer manuellement par l'utilisateur).
  int get preavisLocataireMois {
    switch (this) {
      case BailType.vide:
        return 3;
      case BailType.colocation:
        return 1;
      case BailType.meuble:
        return 1;
      case BailType.mobilite:
        return 1;
      case BailType.saisonnier:
        return 0;
    }
  }

  bool get renouvellementTaciteParDefaut =>
      this != BailType.saisonnier && this != BailType.mobilite;
}

/// Statut d'un contrat de bail dans son cycle de vie.
enum BailStatus {
  brouillon,
  signe,
  enCours,
  termine,
  resilie;

  String get label {
    switch (this) {
      case BailStatus.brouillon:
        return 'Brouillon';
      case BailStatus.signe:
        return 'Signé';
      case BailStatus.enCours:
        return 'En cours';
      case BailStatus.termine:
        return 'Terminé';
      case BailStatus.resilie:
        return 'Résilié';
    }
  }
}

/// Mode de paiement du loyer.
enum ModePaiement {
  virement,
  prelevement,
  cheque,
  especes;

  String get label {
    switch (this) {
      case ModePaiement.virement:
        return 'Virement bancaire';
      case ModePaiement.prelevement:
        return 'Prélèvement automatique';
      case ModePaiement.cheque:
        return 'Chèque';
      case ModePaiement.especes:
        return 'Espèces';
    }
  }
}

/// Contrat de bail entre bailleur et locataire(s) pour un logement donné.
///
/// Stocké dans la box Hive chiffrée `contrats_bail_box`. Génère un PDF via
/// `ContratBailPdfBuilder`.
class ContratBail {
  final String id;

  /// Référence interne lisible : `BAIL-2026-001` etc.
  String reference;

  BailType type;
  BailStatus statut;

  final String logementId;

  /// Locataires concernés (1 = bail standard, >1 = colocation).
  /// Référence vers `Locataire.id` côté Bailleur.
  List<String> locataireIds;

  /// Référent colocataire (pour colocation uniquement, parmi
  /// [locataireIds]). Null = pas de référent désigné.
  String? referentColocataireId;

  /// Adresse du logement à la signature (snapshot, pour ne pas changer si
  /// l'adresse du logement est modifiée ensuite).
  String adresseLogement;
  double surfaceM2;
  int nbPieces;
  String? etage;

  /// Date d'effet et durée.
  DateTime dateDebut;
  int dureeMois;

  /// Date de fin calculée à la signature (mémorisée pour rester stable
  /// même si on change [dureeMois] plus tard via un avenant).
  DateTime dateFin;

  bool renouvellementTacite;
  int preavisBailleurMois;
  int preavisLocataireMois;

  /// Loyer et charges.
  double loyerHC;
  double charges;
  ModePaiement modePaiement;
  String? rib;
  int jourEcheance;

  /// Loyer payable à **terme échu** (en fin de période) plutôt qu'à échoir
  /// (d'avance). Défaut : false (à échoir, l'usage le plus courant).
  bool paiementTermeEchu;

  double depotGarantie;
  bool regularisationChargesAnnuelle;
  double? fraisAgence;

  /// Clauses optionnelles.
  bool revisionAnnuelleIRL;
  bool nonFumeur;
  bool animauxAutorises;
  String? noteAnimaux;
  bool clauseSolidariteColo;

  // Bail meublé : équipements (clés simples → présence/absence).
  Map<String, bool> equipementsMeuble;

  // Bail saisonnier : charges incluses ?
  bool chargesIncluses;

  // Bail mobilité : justificatif (texte libre).
  String? justificatifMobilite;

  /// Signatures électroniques (PNG base64).
  String? signatureBailleurPng;
  DateTime? signatureBailleurAt;

  /// Pour colocation, on stocke les signatures dans une map
  /// `locataireId → png base64`. Pour les autres types, l'entrée unique
  /// `principal` est utilisée.
  Map<String, String> signaturesLocatairesPng;
  Map<String, String> signaturesLocatairesAt;

  /// Hash SHA-256 du contenu signé (intégrité).
  String? integrityHash;

  /// Chemin local du PDF généré (généré + sauvegardé via PdfBuilder).
  String? pdfPath;

  /// Diagnostics rattachés à ce bail (références vers `Diagnostic.id`).
  List<String> diagnosticIds;

  /// Référence vers l'état des lieux d'entrée (si déjà créé).
  String? edlEntreeId;

  /// Notes libres du bailleur.
  String notes;

  // ─── Champs ajoutés (Phase 1b) ───────────────────────────────────────────
  /// Le locataire doit fournir une attestation d'assurance habitation.
  bool attestationAssurance;

  /// Chemin local du fichier d'attestation d'assurance (PDF/image), si fourni.
  String? assuranceFilePath;

  /// Modalités de restitution du dépôt de garantie (texte libre).
  String? modalitesRestitutionDepot;

  /// Description du logement pour le contrat (pièces, usage, équipements).
  String? descriptionLogement;

  /// Mention explicite que l'état des lieux d'entrée a été / sera réalisé.
  bool mentionEtatDesLieux;

  // ─── Champs ajoutés (Phase 2 : bailleur étendu + garants) ─────────────────
  /// Adresse postale du bailleur (snapshot pour le contrat).
  String? bailleurAdresse;
  String? bailleurTelephone;

  /// Le bailleur est une société (SCI, SARL…) plutôt qu'un particulier.
  bool bailleurEstSociete;
  String? bailleurRaisonSociale;
  String? bailleurSiret;
  String? bailleurRepresentant;

  /// Garants (cautions) du bail.
  List<Garant> garants;

  /// Clauses du bail : clauses du catalogue activées + clauses personnalisées.
  List<Clause> clauses;

  /// Chemins locaux des pièces jointes optionnelles (règlement copro, photos,
  /// plan, attestation d'assurance du bailleur, PV d'état des lieux…).
  List<String> annexesOptionnelles;

  final DateTime createdAt;
  DateTime updatedAt;

  // ─── Champs ajoutés (Phase Templates — juin 2026) ─────────────────────────
  /// ID du template ayant servi à créer ce bail (système type
  /// `BAIL_NU_RP_3A` ou UUID utilisateur). Null si bail créé sans template.
  /// Conservé pour audit ; le bail reste indépendant du template après
  /// création (modifier le template ne touche pas les bails existants).
  String? templateSourceId;

  /// Date et heure UTC à laquelle le template a été appliqué.
  DateTime? templateAppliqueLe;

  ContratBail({
    required this.id,
    required this.reference,
    required this.type,
    required this.statut,
    required this.logementId,
    required this.locataireIds,
    this.referentColocataireId,
    required this.adresseLogement,
    required this.surfaceM2,
    required this.nbPieces,
    this.etage,
    required this.dateDebut,
    required this.dureeMois,
    required this.dateFin,
    required this.renouvellementTacite,
    required this.preavisBailleurMois,
    required this.preavisLocataireMois,
    required this.loyerHC,
    required this.charges,
    required this.modePaiement,
    this.rib,
    required this.jourEcheance,
    this.paiementTermeEchu = false,
    required this.depotGarantie,
    required this.regularisationChargesAnnuelle,
    this.fraisAgence,
    this.revisionAnnuelleIRL = true,
    this.nonFumeur = false,
    this.animauxAutorises = false,
    this.noteAnimaux,
    this.clauseSolidariteColo = true,
    Map<String, bool>? equipementsMeuble,
    this.chargesIncluses = false,
    this.justificatifMobilite,
    this.signatureBailleurPng,
    this.signatureBailleurAt,
    Map<String, String>? signaturesLocatairesPng,
    Map<String, String>? signaturesLocatairesAt,
    this.integrityHash,
    this.pdfPath,
    List<String>? diagnosticIds,
    this.edlEntreeId,
    this.notes = '',
    this.attestationAssurance = false,
    this.assuranceFilePath,
    this.modalitesRestitutionDepot,
    this.descriptionLogement,
    this.mentionEtatDesLieux = false,
    this.bailleurAdresse,
    this.bailleurTelephone,
    this.bailleurEstSociete = false,
    this.bailleurRaisonSociale,
    this.bailleurSiret,
    this.bailleurRepresentant,
    List<Garant>? garants,
    List<Clause>? clauses,
    List<String>? annexesOptionnelles,
    required this.createdAt,
    required this.updatedAt,
    this.templateSourceId,
    this.templateAppliqueLe,
  })  : equipementsMeuble = equipementsMeuble ?? {},
        signaturesLocatairesPng = signaturesLocatairesPng ?? {},
        signaturesLocatairesAt = signaturesLocatairesAt ?? {},
        diagnosticIds = diagnosticIds ?? <String>[],
        garants = garants ?? <Garant>[],
        clauses = clauses ?? <Clause>[],
        annexesOptionnelles = annexesOptionnelles ?? <String>[];

  factory ContratBail.create({
    required BailType type,
    required String logementId,
    required List<String> locataireIds,
    required String adresseLogement,
    required double surfaceM2,
    required int nbPieces,
    required DateTime dateDebut,
    required double loyerHC,
    required double charges,
    required double depotGarantie,
    ModePaiement modePaiement = ModePaiement.virement,
    int jourEcheance = 5,
    String? rib,
    String? etage,
    String reference = '',
  }) {
    final now = DateTime.now().toUtc();
    final dureeMois = type.dureeDefautMois;
    final dateFin = DateTime(
      dateDebut.year + ((dateDebut.month - 1 + dureeMois) ~/ 12),
      ((dateDebut.month - 1 + dureeMois) % 12) + 1,
      dateDebut.day,
    );
    return ContratBail(
      id: const Uuid().v4(),
      reference: reference.isEmpty
          ? 'BAIL-${now.year}-${now.millisecondsSinceEpoch.toString().substring(8)}'
          : reference,
      type: type,
      statut: BailStatus.brouillon,
      logementId: logementId,
      locataireIds: List<String>.from(locataireIds),
      adresseLogement: adresseLogement,
      surfaceM2: surfaceM2,
      nbPieces: nbPieces,
      etage: etage,
      dateDebut: dateDebut,
      dureeMois: dureeMois,
      dateFin: dateFin,
      renouvellementTacite: type.renouvellementTaciteParDefaut,
      preavisBailleurMois: type.preavisBailleurMois,
      preavisLocataireMois: type.preavisLocataireMois,
      loyerHC: loyerHC,
      charges: charges,
      modePaiement: modePaiement,
      rib: rib,
      jourEcheance: jourEcheance,
      depotGarantie: depotGarantie,
      regularisationChargesAnnuelle: true,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Crée un nouveau bail pré-rempli à partir d'un [BailTemplate].
  ///
  /// Les valeurs du template (type, durée, dépôt, préavis, clauses,
  /// équipements meublé) sont copiées dans le bail. Le bail garde
  /// `templateSourceId` et `templateAppliqueLe` pour audit.
  ///
  /// Les champs propres au logement (adresse, surface, nbPieces, loyer)
  /// restent à fournir explicitement par l'appelant — ils ne viennent pas du
  /// template (qui est agnostique du logement).
  factory ContratBail.fromTemplate(
    BailTemplate t, {
    required String logementId,
    required List<String> locataireIds,
    required String adresseLogement,
    required double surfaceM2,
    required int nbPieces,
    required DateTime dateDebut,
    required double loyerHC,
    required double charges,
    ModePaiement modePaiement = ModePaiement.virement,
    int jourEcheance = 5,
    String? rib,
    String? etage,
    String reference = '',
  }) {
    final now = DateTime.now().toUtc();
    final dureeMois = t.dureeDefautMois;
    final dateFin = DateTime(
      dateDebut.year + ((dateDebut.month - 1 + dureeMois) ~/ 12),
      ((dateDebut.month - 1 + dureeMois) % 12) + 1,
      dateDebut.day,
    );

    // Dépôt : respecte la règle d'interdiction (bail mobilité) sinon
    // multiplicateur du loyer HC.
    final double depot = t.depotInterdit
        ? 0.0
        : (loyerHC * t.depotMultiplicateurLoyer);

    // Clauses : on instancie des copies indépendantes pour que le bail
    // soit autonome (modifier le template ensuite ne touche pas ce bail).
    final clausesDuTemplate = <Clause>[
      // Clauses du catalogue pré-cochées
      for (final id in t.clausesPreCochees)
        ClauseCatalogue.standard.firstWhere(
          (c) => c.id == id,
          orElse: () => Clause(
            id: id,
            titre: '',
            contenu: '',
            categorie: ClauseCategorie.personnalisee,
            active: false,
          ),
        ).copy(),
      // Clauses personnalisées embarquées dans le template
      ...t.clausesPersoIncluses.map((c) => c.copy()),
    ].where((c) => c.titre.isNotEmpty).toList();

    return ContratBail(
      id: const Uuid().v4(),
      reference: reference.isEmpty
          ? 'BAIL-${now.year}-${now.millisecondsSinceEpoch.toString().substring(8)}'
          : reference,
      type: t.typeBail,
      statut: BailStatus.brouillon,
      logementId: logementId,
      locataireIds: List<String>.from(locataireIds),
      adresseLogement: adresseLogement,
      surfaceM2: surfaceM2,
      nbPieces: nbPieces,
      etage: etage,
      dateDebut: dateDebut,
      dureeMois: dureeMois,
      dateFin: dateFin,
      renouvellementTacite: t.renouvellementTacite,
      preavisBailleurMois: t.preavisBailleurMois,
      preavisLocataireMois: t.preavisLocataireMois,
      loyerHC: loyerHC,
      charges: charges,
      modePaiement: modePaiement,
      rib: rib,
      jourEcheance: jourEcheance,
      depotGarantie: depot,
      regularisationChargesAnnuelle: !t.clausesPreCochees
          .contains('cat_v2_forfait_charges'),
      equipementsMeuble: t.equipementsMeubleDefauts == null
          ? null
          : Map<String, bool>.from(t.equipementsMeubleDefauts!),
      clauses: clausesDuTemplate,
      createdAt: now,
      updatedAt: now,
      templateSourceId: t.id,
      templateAppliqueLe: now,
    );
  }

  double get totalMensuel => loyerHC + charges;

  bool get estColocation =>
      type == BailType.colocation || locataireIds.length > 1;
}

class ContratBailAdapter extends TypeAdapter<ContratBail> {
  @override
  final int typeId = 18;

  @override
  ContratBail read(BinaryReader reader) {
    final n = reader.readByte();
    final f = <int, dynamic>{
      for (var i = 0; i < n; i++) reader.readByte(): reader.read(),
    };
    final rawEquip = f[28] as Map?;
    final equip = <String, bool>{};
    rawEquip?.forEach((k, v) {
      if (k is String && v is bool) equip[k] = v;
    });
    final rawSigPng = f[34] as Map?;
    final sigPng = <String, String>{};
    rawSigPng?.forEach((k, v) {
      if (k is String && v is String) sigPng[k] = v;
    });
    final rawSigAt = f[35] as Map?;
    final sigAt = <String, String>{};
    rawSigAt?.forEach((k, v) {
      if (k is String && v is String) sigAt[k] = v;
    });
    return ContratBail(
      id: f[0] as String,
      reference: f[1] as String,
      type: BailType.values.firstWhere(
        (t) => t.name == (f[2] as String?),
        orElse: () => BailType.vide,
      ),
      statut: BailStatus.values.firstWhere(
        (s) => s.name == (f[3] as String?),
        orElse: () => BailStatus.brouillon,
      ),
      logementId: f[4] as String,
      locataireIds: (f[5] as List).cast<String>(),
      referentColocataireId: f[6] as String?,
      adresseLogement: f[7] as String,
      surfaceM2: (f[8] as num).toDouble(),
      nbPieces: (f[9] as num).toInt(),
      etage: f[10] as String?,
      dateDebut: DateTime.parse(f[11] as String),
      dureeMois: (f[12] as num).toInt(),
      dateFin: DateTime.parse(f[13] as String),
      renouvellementTacite: f[14] as bool,
      preavisBailleurMois: (f[15] as num).toInt(),
      preavisLocataireMois: (f[16] as num).toInt(),
      loyerHC: (f[17] as num).toDouble(),
      charges: (f[18] as num).toDouble(),
      modePaiement: ModePaiement.values.firstWhere(
        (m) => m.name == (f[19] as String?),
        orElse: () => ModePaiement.virement,
      ),
      rib: f[20] as String?,
      jourEcheance: (f[21] as num).toInt(),
      depotGarantie: (f[22] as num).toDouble(),
      regularisationChargesAnnuelle: f[23] as bool,
      fraisAgence: (f[24] as num?)?.toDouble(),
      revisionAnnuelleIRL: (f[25] as bool?) ?? true,
      nonFumeur: (f[26] as bool?) ?? false,
      animauxAutorises: (f[27] as bool?) ?? false,
      equipementsMeuble: equip,
      noteAnimaux: f[29] as String?,
      clauseSolidariteColo: (f[30] as bool?) ?? true,
      chargesIncluses: (f[31] as bool?) ?? false,
      justificatifMobilite: f[32] as String?,
      signatureBailleurPng: f[33] as String?,
      signaturesLocatairesPng: sigPng,
      signaturesLocatairesAt: sigAt,
      signatureBailleurAt: f[36] is String
          ? DateTime.parse(f[36] as String)
          : null,
      integrityHash: f[37] as String?,
      pdfPath: f[38] as String?,
      diagnosticIds: (f[39] as List?)?.cast<String>() ?? <String>[],
      edlEntreeId: f[40] as String?,
      notes: (f[41] as String?) ?? '',
      attestationAssurance: (f[44] as bool?) ?? false,
      assuranceFilePath: f[45] as String?,
      modalitesRestitutionDepot: f[46] as String?,
      descriptionLogement: f[47] as String?,
      mentionEtatDesLieux: (f[48] as bool?) ?? false,
      bailleurAdresse: f[49] as String?,
      bailleurTelephone: f[50] as String?,
      bailleurEstSociete: (f[51] as bool?) ?? false,
      bailleurRaisonSociale: f[52] as String?,
      bailleurSiret: f[53] as String?,
      bailleurRepresentant: f[54] as String?,
      garants: (f[55] as List?)
              ?.map((e) => Garant.fromMap((e as Map).cast<String, dynamic>()))
              .toList() ??
          <Garant>[],
      clauses: (f[56] as List?)
              ?.map((e) => Clause.fromMap((e as Map).cast<String, dynamic>()))
              .toList() ??
          <Clause>[],
      annexesOptionnelles: (f[57] as List?)?.cast<String>() ?? <String>[],
      paiementTermeEchu: (f[58] as bool?) ?? false,
      templateSourceId: f[59] as String?,
      templateAppliqueLe: f[60] is String
          ? DateTime.parse(f[60] as String)
          : null,
      createdAt: DateTime.parse(f[42] as String),
      updatedAt: DateTime.parse(f[43] as String),
    );
  }

  @override
  void write(BinaryWriter writer, ContratBail obj) {
    writer
      ..writeByte(61)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.reference)
      ..writeByte(2)
      ..write(obj.type.name)
      ..writeByte(3)
      ..write(obj.statut.name)
      ..writeByte(4)
      ..write(obj.logementId)
      ..writeByte(5)
      ..write(obj.locataireIds)
      ..writeByte(6)
      ..write(obj.referentColocataireId)
      ..writeByte(7)
      ..write(obj.adresseLogement)
      ..writeByte(8)
      ..write(obj.surfaceM2)
      ..writeByte(9)
      ..write(obj.nbPieces)
      ..writeByte(10)
      ..write(obj.etage)
      ..writeByte(11)
      ..write(obj.dateDebut.toIso8601String())
      ..writeByte(12)
      ..write(obj.dureeMois)
      ..writeByte(13)
      ..write(obj.dateFin.toIso8601String())
      ..writeByte(14)
      ..write(obj.renouvellementTacite)
      ..writeByte(15)
      ..write(obj.preavisBailleurMois)
      ..writeByte(16)
      ..write(obj.preavisLocataireMois)
      ..writeByte(17)
      ..write(obj.loyerHC)
      ..writeByte(18)
      ..write(obj.charges)
      ..writeByte(19)
      ..write(obj.modePaiement.name)
      ..writeByte(20)
      ..write(obj.rib)
      ..writeByte(21)
      ..write(obj.jourEcheance)
      ..writeByte(22)
      ..write(obj.depotGarantie)
      ..writeByte(23)
      ..write(obj.regularisationChargesAnnuelle)
      ..writeByte(24)
      ..write(obj.fraisAgence)
      ..writeByte(25)
      ..write(obj.revisionAnnuelleIRL)
      ..writeByte(26)
      ..write(obj.nonFumeur)
      ..writeByte(27)
      ..write(obj.animauxAutorises)
      ..writeByte(28)
      ..write(obj.equipementsMeuble)
      ..writeByte(29)
      ..write(obj.noteAnimaux)
      ..writeByte(30)
      ..write(obj.clauseSolidariteColo)
      ..writeByte(31)
      ..write(obj.chargesIncluses)
      ..writeByte(32)
      ..write(obj.justificatifMobilite)
      ..writeByte(33)
      ..write(obj.signatureBailleurPng)
      ..writeByte(34)
      ..write(obj.signaturesLocatairesPng)
      ..writeByte(35)
      ..write(obj.signaturesLocatairesAt)
      ..writeByte(36)
      ..write(obj.signatureBailleurAt?.toIso8601String())
      ..writeByte(37)
      ..write(obj.integrityHash)
      ..writeByte(38)
      ..write(obj.pdfPath)
      ..writeByte(39)
      ..write(obj.diagnosticIds)
      ..writeByte(40)
      ..write(obj.edlEntreeId)
      ..writeByte(41)
      ..write(obj.notes)
      ..writeByte(42)
      ..write(obj.createdAt.toIso8601String())
      ..writeByte(43)
      ..write(obj.updatedAt.toIso8601String())
      ..writeByte(44)
      ..write(obj.attestationAssurance)
      ..writeByte(45)
      ..write(obj.assuranceFilePath)
      ..writeByte(46)
      ..write(obj.modalitesRestitutionDepot)
      ..writeByte(47)
      ..write(obj.descriptionLogement)
      ..writeByte(48)
      ..write(obj.mentionEtatDesLieux)
      ..writeByte(49)
      ..write(obj.bailleurAdresse)
      ..writeByte(50)
      ..write(obj.bailleurTelephone)
      ..writeByte(51)
      ..write(obj.bailleurEstSociete)
      ..writeByte(52)
      ..write(obj.bailleurRaisonSociale)
      ..writeByte(53)
      ..write(obj.bailleurSiret)
      ..writeByte(54)
      ..write(obj.bailleurRepresentant)
      ..writeByte(55)
      ..write(obj.garants.map((g) => g.toMap()).toList())
      ..writeByte(56)
      ..write(obj.clauses.map((c) => c.toMap()).toList())
      ..writeByte(57)
      ..write(obj.annexesOptionnelles)
      ..writeByte(58)
      ..write(obj.paiementTermeEchu)
      ..writeByte(59)
      ..write(obj.templateSourceId)
      ..writeByte(60)
      ..write(obj.templateAppliqueLe?.toIso8601String());
  }
}
