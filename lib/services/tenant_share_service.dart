import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../core/backup/backup_codec.dart';
import '../core/constants.dart';
import '../core/pdf/etat_des_lieux_pdf.dart';
import '../core/storage/local_database.dart';
import '../models/element_piece.dart';
import '../models/etat_des_lieux.dart';
import '../models/etat_element.dart';
import '../models/locataire.dart';
import '../models/logement.dart';
import '../models/piece.dart';
import '../models/quittance.dart';
import '../models/received_bundle.dart';
import 'etat_des_lieux_service.dart';
import 'locataire_service.dart';
import 'logement_service.dart';
import 'quittance_service.dart';

/// Résultat d'un partage généré par le propriétaire.
class TenantShareResult {
  final File file;
  final String code;
  final String locataireName;
  final int edlCount;
  final int quittanceCount;

  const TenantShareResult({
    required this.file,
    required this.code,
    required this.locataireName,
    required this.edlCount,
    required this.quittanceCount,
  });
}

/// Métadonnées d'un partage déchiffré.
class ReceivedShareContent {
  final String fromName;
  final String fromEmail;
  final DateTime sharedAt;
  final Map<String, dynamic>? locataire;
  final List<Map<String, dynamic>> logements;
  final List<Map<String, dynamic>> etatDesLieux;
  final List<Map<String, dynamic>> quittances;

  const ReceivedShareContent({
    required this.fromName,
    required this.fromEmail,
    required this.sharedAt,
    required this.locataire,
    required this.logements,
    required this.etatDesLieux,
    required this.quittances,
  });
}

/// Gère les partages locaux propriétaire <-> locataire, transportés via la
/// feuille de partage OS (AirDrop / Nearby Share / Bluetooth / Email...).
///
/// Fichier : `.adls` — même format binaire qu'un `.adlb` (ADLB magic), mais
/// le payload JSON a un `kind: 'tenant_share'` et est filtré sur un seul
/// locataire. Protégé par un code de 8 caractères généré aléatoirement.
class TenantShareService extends ChangeNotifier {
  /// Version courante du format `.adls`. Incrémenter à chaque changement
  /// incompatible du schéma JSON. Les fichiers avec une version supérieure
  /// sont rejetés à la lecture pour éviter les corruptions silencieuses.
  static const int formatVersion = 3;

  static const _codeAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  static const _codeLength = 8;

  /// Lève [BackupFormatException] si le payload n'est pas un partage
  /// locataire ou si sa version dépasse celle supportée par l'app.
  static void _assertSchema(Map<String, dynamic> decoded) {
    if (decoded['kind'] != 'tenant_share') {
      throw const BackupFormatException(
        'Ce fichier n\'est pas un partage locataire.',
      );
    }
    final v = decoded['version'];
    if (v is! int) {
      throw const BackupFormatException(
        'Version du partage manquante ou invalide.',
      );
    }
    if (v > formatVersion) {
      throw BackupFormatException(
        'Partage version $v incompatible : mettez à jour l\'application '
        '(version supportée : $formatVersion).',
      );
    }
  }

  /// Liste des bundles reçus par le locataire, du plus récent au plus ancien.
  List<ReceivedBundle> get receivedBundles {
    final items = LocalDatabase.receivedBundlesBox.values.toList();
    items.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    return items;
  }

  ReceivedBundle? bundleById(String id) =>
      LocalDatabase.receivedBundlesBox.get(id);

  Future<void> deleteBundle(String id) async {
    await LocalDatabase.receivedBundlesBox.delete(id);
    notifyListeners();
  }

  /// Crée un partage pour [locataire] contenant tous les EDL et quittances
  /// qui le concernent. Retourne le fichier + le code à communiquer.
  ///
  /// Si [quittanceIds] est fourni, seules les quittances du locataire dont
  /// l'`id` figure dans ce set sont incluses dans le bundle (sinon : toutes
  /// les quittances du locataire). Permet à l'utilisateur de cocher / décocher
  /// manuellement chaque quittance avant l'envoi.
  Future<TenantShareResult> createShareForLocataire({
    required Locataire locataire,
    Set<String>? quittanceIds,
  }) async {
    final bailleur = LocalDatabase.userBox.get(AppConstants.userProfileKey);
    if (bailleur == null) {
      throw StateError('Aucun profil bailleur — impossible de créer un partage.');
    }

    final edls = LocalDatabase.etatDesLieuxBox.values
        .where((e) => e.locataireId == locataire.id)
        .toList();
    final quittances = LocalDatabase.quittancesBox.values
        .where((q) =>
            q.locataireId == locataire.id &&
            (quittanceIds == null || quittanceIds.contains(q.id)))
        .toList();
    final logementIds = {
      ...edls.map((e) => e.logementId),
      ...quittances.map((q) => q.logementId),
    };
    final logements = LocalDatabase.logementsBox.values
        .where((l) => logementIds.contains(l.id))
        .toList();

    // Génère un PDF complet (avec photos) pour chaque EDL : embarqué en
    // base64 dans le payload `.adls` pour que le locataire puisse l'ouvrir
    // directement. Augmente la taille du bundle mais évite au locataire de
    // demander le PDF séparément.
    final edlMaps = <Map<String, dynamic>>[];
    for (final e in edls) {
      final logement = LocalDatabase.logementsBox.get(e.logementId);
      if (logement == null) {
        edlMaps.add(_edlToMap(e));
        continue;
      }
      final wallPhotos = LocalDatabase.plansLogementBox.values
          .where((p) => p.logementId == logement.id)
          .expand((p) => p.wallPhotos)
          .where((w) => w.etatId == null || w.etatId == e.id)
          .toList();
      final plans = LocalDatabase.plansLogementBox.values
          .where((p) => p.logementId == logement.id)
          .toList();
      String? pdfBase64;
      try {
        final pdf = await EtatDesLieuxPdfBuilder.build(
          edl: e,
          bailleur: bailleur,
          logement: logement,
          locataire: locataire,
          wallPhotos: wallPhotos,
          plans: plans,
        );
        final bytes = await pdf.save();
        pdfBase64 = base64Encode(bytes);
      } catch (err, stack) {
        debugPrint(
            'TenantShareService PDF EDL ${e.id} échec : $err\n$stack');
      }
      final edlMap = _edlToMap(e);
      if (pdfBase64 != null) edlMap['pdfBase64'] = pdfBase64;
      edlMaps.add(edlMap);
    }

    final payload = <String, dynamic>{
      'kind': 'tenant_share',
      'version': TenantShareService.formatVersion,
      'appVersion': AppConstants.appVersion,
      'sharedAt': DateTime.now().toUtc().toIso8601String(),
      'from': {
        'firstName': bailleur.firstName,
        'lastName': bailleur.lastName,
        'email': bailleur.email,
      },
      'locataire': {
        'id': locataire.id,
        'firstName': locataire.firstName,
        'lastName': locataire.lastName,
        'email': locataire.email,
      },
      'logements': logements.map(_logementToMap).toList(),
      'etatDesLieux': edlMaps,
      'quittances': quittances.map(_quittanceToMap).toList(),
    };

    final code = _generateCode();
    final encrypted = await BackupCodec.encryptAsync(
      jsonPayload: jsonEncode(payload),
      passphrase: code,
    );
    final dir = await getTemporaryDirectory();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final safe = locataire.fullName.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');
    final file = File('${dir.path}/partage_$safe.adls');
    await file.writeAsBytes(encrypted, flush: true);

    return TenantShareResult(
      file: file,
      code: code,
      locataireName: locataire.fullName,
      edlCount: edls.length,
      quittanceCount: quittances.length,
    );
  }

  /// Déchiffre un fichier `.adls` reçu, vérifie son kind et retourne le
  /// contenu sans le persister.
  Future<ReceivedShareContent> previewShare({
    required Uint8List bytes,
    required String code,
  }) async {
    final jsonText = await BackupCodec.decryptAsync(
      bytes: bytes,
      passphrase: code.trim().toUpperCase(),
    );
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map<String, dynamic>) {
      throw const BackupFormatException('Payload JSON invalide');
    }
    _assertSchema(decoded);
    return _toContent(decoded);
  }

  /// Persiste un partage reçu dans la boîte des bundles du locataire et,
  /// si les services sont fournis, copie automatiquement les entités dans
  /// les rubriques natives ("Mes quittances", "Mes états des lieux"...).
  Future<ReceivedBundle> saveReceivedShare({
    required Uint8List bytes,
    required String code,
    LogementService? logementService,
    LocataireService? locataireService,
    EtatDesLieuxService? etatDesLieuxService,
    QuittanceService? quittanceService,
  }) async {
    final jsonText = await BackupCodec.decryptAsync(
      bytes: bytes,
      passphrase: code.trim().toUpperCase(),
    );
    final decoded = jsonDecode(jsonText) as Map<String, dynamic>;
    _assertSchema(decoded);
    final from = decoded['from'] as Map<String, dynamic>;
    final bundle = ReceivedBundle.create(
      fromName: '${from['firstName']} ${from['lastName']}',
      fromEmail: from['email'] as String,
      payloadJson: jsonText,
    );
    await LocalDatabase.receivedBundlesBox.put(bundle.id, bundle);

    if (logementService != null &&
        locataireService != null &&
        etatDesLieuxService != null &&
        quittanceService != null) {
      try {
        await applyToServices(
          _toContent(decoded),
          logementService: logementService,
          locataireService: locataireService,
          etatDesLieuxService: etatDesLieuxService,
          quittanceService: quittanceService,
        );
      } catch (_) {
        // L'auto-import est best-effort : le bundle reste accessible dans
        // "Documents reçus" même si la copie native échoue.
      }
    }

    notifyListeners();
    return bundle;
  }

  /// Désérialise le contenu d'un [ReceivedBundle] stocké.
  ReceivedShareContent decodeBundle(ReceivedBundle bundle) {
    final decoded = jsonDecode(bundle.payloadJson) as Map<String, dynamic>;
    _assertSchema(decoded);
    return _toContent(decoded);
  }

  ReceivedShareContent _toContent(Map<String, dynamic> decoded) {
    final from = decoded['from'] as Map<String, dynamic>;
    return ReceivedShareContent(
      fromName: '${from['firstName']} ${from['lastName']}',
      fromEmail: from['email'] as String,
      sharedAt: DateTime.parse(decoded['sharedAt'] as String),
      locataire: decoded['locataire'] is Map<String, dynamic>
          ? decoded['locataire'] as Map<String, dynamic>
          : null,
      logements:
          (decoded['logements'] as List).cast<Map<String, dynamic>>(),
      etatDesLieux:
          (decoded['etatDesLieux'] as List).cast<Map<String, dynamic>>(),
      quittances:
          (decoded['quittances'] as List).cast<Map<String, dynamic>>(),
    );
  }

  /// Copie les logements, EDL et quittances du bundle dans les rubriques
  /// natives du locataire. Idempotent (upsert par id) — un nouveau partage
  /// pour le même locataire écrase les versions précédentes.
  ///
  /// Les EDL finalisés et les quittances déjà présents avec le même id sont
  /// remplacés (la version la plus à jour gagne).
  Future<void> applyToServices(
    ReceivedShareContent content, {
    required LogementService logementService,
    required LocataireService locataireService,
    required EtatDesLieuxService etatDesLieuxService,
    required QuittanceService quittanceService,
  }) async {
    final locataireMap = content.locataire;
    if (locataireMap == null || locataireMap['id'] is! String) {
      // Bundle v1 sans locataireId — rien à faire côté auto-import,
      // le bundle reste consultable dans "Documents reçus".
      return;
    }
    final locataireId = locataireMap['id'] as String;

    if (locataireService.byId(locataireId) == null) {
      final synthetic = Locataire(
        id: locataireId,
        firstName: (locataireMap['firstName'] as String?) ?? '',
        lastName: (locataireMap['lastName'] as String?) ?? '',
        email: (locataireMap['email'] as String?) ?? '',
        phone: null,
        logementIds: <String>[],
        dateEntree: null,
        notes: 'Importé depuis un partage de ${content.fromName}.',
        createdAt: content.sharedAt,
        updatedAt: content.sharedAt,
      );
      await locataireService.add(synthetic);
    }

    for (final m in content.logements) {
      final logement = _logementFromMap(m);
      final existing = logementService.byId(logement.id);
      if (existing == null) {
        await logementService.add(logement);
      }
      await locataireService.assignToLogement(locataireId, logement.id);
    }

    for (final m in content.etatDesLieux) {
      final id = m['id'] as String?;
      if (id == null) continue;
      if (etatDesLieuxService.byId(id) != null) continue;
      final edl = _edlFromMap(m, locataireId);
      await etatDesLieuxService.importFromShare(edl);
    }

    for (final m in content.quittances) {
      final id = m['id'] as String?;
      if (id == null) continue;
      if (quittanceService.byId(id) != null) continue;
      final q = _quittanceFromMap(m);
      q.bailleurName ??= content.fromName;
      q.bailleurEmail ??= content.fromEmail;
      await quittanceService.add(q);
    }
  }

  String _generateCode() {
    final rnd = Random.secure();
    return List.generate(
      _codeLength,
      (_) => _codeAlphabet[rnd.nextInt(_codeAlphabet.length)],
    ).join();
  }

  Map<String, dynamic> _logementToMap(Logement l) => {
        'id': l.id,
        'libelle': l.libelle,
        'adresse': l.adresse,
        'codePostal': l.codePostal,
        'ville': l.ville,
        'type': l.type.name,
        'surface': l.surface,
        'nbPieces': l.nbPieces,
        'loyerHC': l.loyerHC,
        'charges': l.charges,
        'equipements': l.equipements,
        'notes': l.notes,
        'createdAt': l.createdAt.toUtc().toIso8601String(),
        'updatedAt': l.updatedAt.toUtc().toIso8601String(),
      };

  Map<String, dynamic> _elementToMap(ElementPiece e) => {
        'id': e.id,
        'nom': e.nom,
        'etat': e.etat.name,
        'description': e.description,
        // photoPaths non incluses — elles pointent vers des fichiers locaux
        // du propriétaire, invalides côté locataire.
      };

  Map<String, dynamic> _pieceToMap(Piece p) => {
        'id': p.id,
        'nom': p.nom,
        'elements': p.elements.map(_elementToMap).toList(),
      };

  Map<String, dynamic> _edlToMap(EtatDesLieux e) => {
        'id': e.id,
        'type': e.type.name,
        'logementId': e.logementId,
        'locataireId': e.locataireId,
        'date': e.date.toUtc().toIso8601String(),
        'status': e.status.name,
        'pieces': e.pieces.map(_pieceToMap).toList(),
        'proprietaireSignaturePng': e.proprietaireSignaturePng,
        'proprietaireSignatureAt':
            e.proprietaireSignatureAt?.toUtc().toIso8601String(),
        'locataireSignaturePng': e.locataireSignaturePng,
        'locataireSignatureAt':
            e.locataireSignatureAt?.toUtc().toIso8601String(),
        'locataireCode': e.locataireCode,
        'integrityHash': e.integrityHash,
        'notes': e.notes,
        'bailleurAdresse': e.bailleurAdresse,
        'nombreCles': e.nombreCles,
        'releveCompteurGaz': e.releveCompteurGaz,
        'releveCompteurEauChaude': e.releveCompteurEauChaude,
        'releveCompteurEauFroide': e.releveCompteurEauFroide,
        'releveCompteurElecJour': e.releveCompteurElecJour,
        'releveCompteurElecNuit': e.releveCompteurElecNuit,
        'createdAt': e.createdAt.toUtc().toIso8601String(),
        'updatedAt': e.updatedAt.toUtc().toIso8601String(),
      };

  Map<String, dynamic> _quittanceToMap(Quittance q) => {
        'id': q.id,
        'logementId': q.logementId,
        'locataireId': q.locataireId,
        'periodYear': q.periodYear,
        'periodMonth': q.periodMonth,
        'loyerHC': q.loyerHC,
        'charges': q.charges,
        'datePaiement': q.datePaiement.toUtc().toIso8601String(),
        'dateEmission': q.dateEmission.toUtc().toIso8601String(),
        'notes': q.notes,
        'createdAt': q.createdAt.toUtc().toIso8601String(),
        'integrityHash': q.integrityHash,
      };

  Logement _logementFromMap(Map<String, dynamic> m) {
    final now = DateTime.now().toUtc();
    return Logement(
      id: m['id'] as String,
      libelle: (m['libelle'] as String?) ?? '',
      adresse: (m['adresse'] as String?) ?? '',
      codePostal: (m['codePostal'] as String?) ?? '',
      ville: (m['ville'] as String?) ?? '',
      type: LogementType.fromString((m['type'] as String?) ?? 'autre'),
      surface: (m['surface'] as num?)?.toDouble() ?? 0,
      nbPieces: (m['nbPieces'] as num?)?.toInt() ?? 0,
      loyerHC: (m['loyerHC'] as num?)?.toDouble() ?? 0,
      charges: (m['charges'] as num?)?.toDouble() ?? 0,
      equipements: (m['equipements'] as List?)?.cast<String>() ?? <String>[],
      notes: (m['notes'] as String?) ?? '',
      createdAt: m['createdAt'] is String
          ? DateTime.parse(m['createdAt'] as String)
          : now,
      updatedAt: m['updatedAt'] is String
          ? DateTime.parse(m['updatedAt'] as String)
          : now,
    );
  }

  ElementPiece _elementFromMap(Map<String, dynamic> m) {
    return ElementPiece(
      id: (m['id'] as String?) ?? const Uuid().v4(),
      nom: (m['nom'] as String?) ?? '',
      etat: EtatElement.fromString((m['etat'] as String?) ?? 'bon'),
      description: (m['description'] as String?) ?? '',
      photoPaths: <String>[],
    );
  }

  Piece _pieceFromMap(Map<String, dynamic> m) {
    return Piece(
      id: (m['id'] as String?) ?? const Uuid().v4(),
      nom: (m['nom'] as String?) ?? '',
      elements: ((m['elements'] as List?) ?? <dynamic>[])
          .cast<Map<String, dynamic>>()
          .map(_elementFromMap)
          .toList(),
    );
  }

  EtatDesLieux _edlFromMap(Map<String, dynamic> m, String fallbackLocataireId) {
    DateTime? parseDt(dynamic v) =>
        v is String && v.isNotEmpty ? DateTime.parse(v) : null;
    final now = DateTime.now().toUtc();
    return EtatDesLieux(
      id: m['id'] as String,
      type: EtatDesLieuxType.fromString((m['type'] as String?) ?? 'entree'),
      logementId: (m['logementId'] as String?) ?? '',
      locataireId: (m['locataireId'] as String?) ?? fallbackLocataireId,
      date: m['date'] is String
          ? DateTime.parse(m['date'] as String)
          : now,
      status: EtatDesLieuxStatus.fromString(
        (m['status'] as String?) ?? 'finalise',
      ),
      pieces: ((m['pieces'] as List?) ?? <dynamic>[])
          .cast<Map<String, dynamic>>()
          .map(_pieceFromMap)
          .toList(),
      proprietaireSignaturePng: m['proprietaireSignaturePng'] as String?,
      proprietaireSignatureAt: parseDt(m['proprietaireSignatureAt']),
      locataireCode: m['locataireCode'] as String?,
      locataireSignaturePng: m['locataireSignaturePng'] as String?,
      locataireSignatureAt: parseDt(m['locataireSignatureAt']),
      integrityHash: m['integrityHash'] as String?,
      notes: (m['notes'] as String?) ?? '',
      bailleurAdresse: m['bailleurAdresse'] as String?,
      nombreCles: (m['nombreCles'] as num?)?.toInt(),
      releveCompteurGaz: m['releveCompteurGaz'] as String?,
      releveCompteurEauChaude: m['releveCompteurEauChaude'] as String?,
      releveCompteurEauFroide: m['releveCompteurEauFroide'] as String?,
      releveCompteurElecJour: m['releveCompteurElecJour'] as String?,
      releveCompteurElecNuit: m['releveCompteurElecNuit'] as String?,
      createdAt: m['createdAt'] is String
          ? DateTime.parse(m['createdAt'] as String)
          : now,
      updatedAt: m['updatedAt'] is String
          ? DateTime.parse(m['updatedAt'] as String)
          : now,
    );
  }

  Quittance _quittanceFromMap(Map<String, dynamic> m) {
    final created = m['createdAt'] is String
        ? DateTime.parse(m['createdAt'] as String)
        : DateTime.parse(m['dateEmission'] as String);
    return Quittance(
      id: m['id'] as String,
      logementId: m['logementId'] as String,
      locataireId: m['locataireId'] as String,
      periodYear: (m['periodYear'] as num).toInt(),
      periodMonth: (m['periodMonth'] as num).toInt(),
      loyerHC: (m['loyerHC'] as num).toDouble(),
      charges: (m['charges'] as num).toDouble(),
      datePaiement: DateTime.parse(m['datePaiement'] as String),
      dateEmission: DateTime.parse(m['dateEmission'] as String),
      notes: (m['notes'] as String?) ?? '',
      createdAt: created,
      integrityHash: m['integrityHash'] as String?,
      bailleurName: m['bailleurName'] as String?,
      bailleurEmail: m['bailleurEmail'] as String?,
    );
  }
}
