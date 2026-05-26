import 'package:flutter/foundation.dart';

import '../core/storage/local_database.dart';
import '../core/storage/photo_storage.dart';
import '../models/etat_des_lieux.dart';

class EtatDesLieuxException implements Exception {
  final String message;
  EtatDesLieuxException(this.message);
  @override
  String toString() => 'EtatDesLieuxException: $message';
}

class EtatDesLieuxService extends ChangeNotifier {
  List<EtatDesLieux> get all {
    final items = LocalDatabase.etatDesLieuxBox.values.toList();
    items.sort((a, b) => b.date.compareTo(a.date));
    return items;
  }

  EtatDesLieux? byId(String id) => LocalDatabase.etatDesLieuxBox.get(id);

  List<EtatDesLieux> byLogement(String logementId) =>
      all.where((e) => e.logementId == logementId).toList();

  List<EtatDesLieux> byLocataire(String locataireId) =>
      all.where((e) => e.locataireId == locataireId).toList();

  Future<EtatDesLieux> save(EtatDesLieux edl) async {
    if (edl.isFinalized) {
      throw EtatDesLieuxException(
        'Cet état des lieux est finalisé, il ne peut plus être modifié.',
      );
    }
    edl.updatedAt = DateTime.now().toUtc();
    await LocalDatabase.etatDesLieuxBox.put(edl.id, edl);
    notifyListeners();
    return edl;
  }

  /// Enregistre la signature du propriétaire et passe l'EDL en attente de
  /// signature manuscrite du locataire.
  Future<void> signAsProprietaire(
    EtatDesLieux edl, {
    required String signaturePngBase64,
  }) async {
    if (edl.isFinalized) {
      throw EtatDesLieuxException('EDL déjà finalisé.');
    }
    edl.proprietaireSignaturePng = signaturePngBase64;
    edl.proprietaireSignatureAt = DateTime.now().toUtc();
    edl.status = EtatDesLieuxStatus.enAttenteSignatureLocataire;
    edl.updatedAt = DateTime.now().toUtc();
    await LocalDatabase.etatDesLieuxBox.put(edl.id, edl);
    notifyListeners();
  }

  /// Enregistre la signature manuscrite du locataire et finalise l'EDL.
  Future<void> signAsLocataire(
    EtatDesLieux edl, {
    required String signaturePngBase64,
  }) async {
    if (edl.status != EtatDesLieuxStatus.enAttenteSignatureLocataire) {
      throw EtatDesLieuxException(
        'Cet EDL n\'est pas en attente de signature locataire.',
      );
    }
    edl.locataireSignaturePng = signaturePngBase64;
    edl.locataireSignatureAt = DateTime.now().toUtc();
    edl.status = EtatDesLieuxStatus.finalise;
    edl.updatedAt = DateTime.now().toUtc();
    edl.integrityHash = edl.computeIntegrityHash();
    await LocalDatabase.etatDesLieuxBox.put(edl.id, edl);
    notifyListeners();
  }

  /// Applique une signature locataire reçue par fichier `.adlr` (retour
  /// signé renvoyé depuis ADDA Locataire). Vérifie que l'EDL existe encore
  /// en attente de signature et que le hash pré-signature correspond, pour
  /// éviter d'appliquer une signature à un EDL modifié entre-temps.
  Future<EtatDesLieux> applyLocataireSignatureFromShare({
    required String edlId,
    required String preSignatureHash,
    required String signaturePngBase64,
    required DateTime signedAt,
  }) async {
    final edl = byId(edlId);
    if (edl == null) {
      throw EtatDesLieuxException(
        'EDL introuvable. La signature ne peut pas être appliquée.',
      );
    }
    if (edl.status != EtatDesLieuxStatus.enAttenteSignatureLocataire) {
      throw EtatDesLieuxException(
        'Cet EDL n\'est pas en attente de signature locataire.',
      );
    }
    final expected = edl.computePreSignatureHash();
    if (expected != preSignatureHash) {
      throw EtatDesLieuxException(
        'Le document a été modifié depuis l\'envoi au locataire. '
        'Signature refusée.',
      );
    }
    edl.locataireSignaturePng = signaturePngBase64;
    edl.locataireSignatureAt = signedAt.toUtc();
    edl.status = EtatDesLieuxStatus.finalise;
    edl.updatedAt = DateTime.now().toUtc();
    edl.integrityHash = edl.computeIntegrityHash();
    await LocalDatabase.etatDesLieuxBox.put(edl.id, edl);
    notifyListeners();
    return edl;
  }

  /// Abandonne le processus de signature avant finalisation.
  Future<void> revertToDraft(EtatDesLieux edl) async {
    if (edl.isFinalized) {
      throw EtatDesLieuxException('Impossible : EDL finalisé.');
    }
    edl.status = EtatDesLieuxStatus.brouillon;
    edl.proprietaireSignaturePng = null;
    edl.proprietaireSignatureAt = null;
    edl.locataireCode = null;
    edl.locataireSignaturePng = null;
    edl.locataireSignatureAt = null;
    edl.updatedAt = DateTime.now().toUtc();
    await LocalDatabase.etatDesLieuxBox.put(edl.id, edl);
    notifyListeners();
  }

  /// Importe un EDL provenant d'un partage locataire (peut être finalisé).
  /// L'EDL est stocké tel quel — aucun recalcul de hash, ce qui préserve
  /// la signature originale.
  Future<void> importFromShare(EtatDesLieux edl) async {
    await LocalDatabase.etatDesLieuxBox.put(edl.id, edl);
    notifyListeners();
  }

  Future<void> delete(String id) async {
    final edl = byId(id);
    if (edl == null) return;
    await PhotoStorage.deleteAllForEtat(id);
    await LocalDatabase.etatDesLieuxBox.delete(id);
    notifyListeners();
  }

  int get count => LocalDatabase.etatDesLieuxBox.length;

  /// Adresse bailleur la plus récemment renseignée parmi les EDL existants
  /// (utilisée pour pré-remplir un nouvel EDL). Null si aucune trouvée.
  String? lastBailleurAdresse() {
    final items = LocalDatabase.etatDesLieuxBox.values
        .where((e) =>
            e.bailleurAdresse != null && e.bailleurAdresse!.trim().isNotEmpty)
        .toList();
    if (items.isEmpty) return null;
    items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return items.first.bailleurAdresse;
  }
}
