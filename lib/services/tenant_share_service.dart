import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/backup/backup_codec.dart';
import '../core/constants.dart';
import '../core/storage/local_database.dart';
import '../models/element_piece.dart';
import '../models/etat_des_lieux.dart';
import '../models/locataire.dart';
import '../models/logement.dart';
import '../models/piece.dart';
import '../models/quittance.dart';
import '../models/received_bundle.dart';

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
  final List<Map<String, dynamic>> logements;
  final List<Map<String, dynamic>> etatDesLieux;
  final List<Map<String, dynamic>> quittances;

  const ReceivedShareContent({
    required this.fromName,
    required this.fromEmail,
    required this.sharedAt,
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
  static const _codeAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  static const _codeLength = 8;

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
  Future<TenantShareResult> createShareForLocataire({
    required Locataire locataire,
  }) async {
    final bailleur = LocalDatabase.userBox.get(AppConstants.userProfileKey);
    if (bailleur == null) {
      throw StateError('Aucun profil bailleur — impossible de créer un partage.');
    }

    final edls = LocalDatabase.etatDesLieuxBox.values
        .where((e) => e.locataireId == locataire.id)
        .toList();
    final quittances = LocalDatabase.quittancesBox.values
        .where((q) => q.locataireId == locataire.id)
        .toList();
    final logementIds = {
      ...edls.map((e) => e.logementId),
      ...quittances.map((q) => q.logementId),
    };
    final logements = LocalDatabase.logementsBox.values
        .where((l) => logementIds.contains(l.id))
        .toList();

    final payload = <String, dynamic>{
      'kind': 'tenant_share',
      'version': 1,
      'appVersion': AppConstants.appVersion,
      'sharedAt': DateTime.now().toUtc().toIso8601String(),
      'from': {
        'firstName': bailleur.firstName,
        'lastName': bailleur.lastName,
        'email': bailleur.email,
      },
      'locataire': {
        'firstName': locataire.firstName,
        'lastName': locataire.lastName,
        'email': locataire.email,
      },
      'logements': logements.map(_logementToMap).toList(),
      'etatDesLieux': edls.map(_edlToMap).toList(),
      'quittances': quittances.map(_quittanceToMap).toList(),
    };

    final code = _generateCode();
    final encrypted = BackupCodec.encrypt(
      jsonPayload: jsonEncode(payload),
      passphrase: code,
    );
    final dir = await getTemporaryDirectory();
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
  ReceivedShareContent previewShare({
    required Uint8List bytes,
    required String code,
  }) {
    final jsonText =
        BackupCodec.decrypt(bytes: bytes, passphrase: code.trim().toUpperCase());
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map<String, dynamic>) {
      throw const BackupFormatException('Payload JSON invalide');
    }
    if (decoded['kind'] != 'tenant_share') {
      throw const BackupFormatException(
        'Ce fichier n\'est pas un partage locataire.',
      );
    }
    final from = decoded['from'] as Map<String, dynamic>;
    return ReceivedShareContent(
      fromName: '${from['firstName']} ${from['lastName']}',
      fromEmail: from['email'] as String,
      sharedAt: DateTime.parse(decoded['sharedAt'] as String),
      logements:
          (decoded['logements'] as List).cast<Map<String, dynamic>>(),
      etatDesLieux:
          (decoded['etatDesLieux'] as List).cast<Map<String, dynamic>>(),
      quittances:
          (decoded['quittances'] as List).cast<Map<String, dynamic>>(),
    );
  }

  /// Persiste un partage reçu dans la boîte des bundles du locataire.
  Future<ReceivedBundle> saveReceivedShare({
    required Uint8List bytes,
    required String code,
  }) async {
    final jsonText =
        BackupCodec.decrypt(bytes: bytes, passphrase: code.trim().toUpperCase());
    final decoded = jsonDecode(jsonText) as Map<String, dynamic>;
    if (decoded['kind'] != 'tenant_share') {
      throw const BackupFormatException(
        'Ce fichier n\'est pas un partage locataire.',
      );
    }
    final from = decoded['from'] as Map<String, dynamic>;
    final bundle = ReceivedBundle.create(
      fromName: '${from['firstName']} ${from['lastName']}',
      fromEmail: from['email'] as String,
      payloadJson: jsonText,
    );
    await LocalDatabase.receivedBundlesBox.put(bundle.id, bundle);
    notifyListeners();
    return bundle;
  }

  /// Désérialise le contenu d'un [ReceivedBundle] stocké.
  ReceivedShareContent decodeBundle(ReceivedBundle bundle) {
    final decoded = jsonDecode(bundle.payloadJson) as Map<String, dynamic>;
    final from = decoded['from'] as Map<String, dynamic>;
    return ReceivedShareContent(
      fromName: '${from['firstName']} ${from['lastName']}',
      fromEmail: from['email'] as String,
      sharedAt: DateTime.parse(decoded['sharedAt'] as String),
      logements:
          (decoded['logements'] as List).cast<Map<String, dynamic>>(),
      etatDesLieux:
          (decoded['etatDesLieux'] as List).cast<Map<String, dynamic>>(),
      quittances:
          (decoded['quittances'] as List).cast<Map<String, dynamic>>(),
    );
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
      };

  Map<String, dynamic> _elementToMap(ElementPiece e) => {
        'nom': e.nom,
        'etat': e.etat.name,
        'description': e.description,
        // photoPaths non incluses — elles pointent vers des fichiers locaux
        // du propriétaire, invalides côté locataire.
      };

  Map<String, dynamic> _pieceToMap(Piece p) => {
        'nom': p.nom,
        'elements': p.elements.map(_elementToMap).toList(),
      };

  Map<String, dynamic> _edlToMap(EtatDesLieux e) => {
        'id': e.id,
        'type': e.type.name,
        'logementId': e.logementId,
        'date': e.date.toUtc().toIso8601String(),
        'status': e.status.name,
        'pieces': e.pieces.map(_pieceToMap).toList(),
        'proprietaireSignaturePng': e.proprietaireSignaturePng,
        'proprietaireSignatureAt':
            e.proprietaireSignatureAt?.toUtc().toIso8601String(),
        'locataireSignatureAt':
            e.locataireSignatureAt?.toUtc().toIso8601String(),
        'integrityHash': e.integrityHash,
        'notes': e.notes,
      };

  Map<String, dynamic> _quittanceToMap(Quittance q) => {
        'id': q.id,
        'logementId': q.logementId,
        'periodYear': q.periodYear,
        'periodMonth': q.periodMonth,
        'loyerHC': q.loyerHC,
        'charges': q.charges,
        'datePaiement': q.datePaiement.toUtc().toIso8601String(),
        'dateEmission': q.dateEmission.toUtc().toIso8601String(),
        'notes': q.notes,
        'integrityHash': q.integrityHash,
      };
}
