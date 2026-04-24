import 'dart:math';

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

  /// Enregistre la signature du propriétaire et génère un code temporaire
  /// à 6 caractères que le locataire devra saisir pour co-signer.
  Future<String> signAsProprietaire(
    EtatDesLieux edl, {
    required String signaturePngBase64,
  }) async {
    if (edl.isFinalized) {
      throw EtatDesLieuxException('EDL déjà finalisé.');
    }
    edl.proprietaireSignaturePng = signaturePngBase64;
    edl.proprietaireSignatureAt = DateTime.now().toUtc();
    edl.locataireCode = _generateCode();
    edl.status = EtatDesLieuxStatus.enAttenteSignatureLocataire;
    edl.updatedAt = DateTime.now().toUtc();
    await LocalDatabase.etatDesLieuxBox.put(edl.id, edl);
    notifyListeners();
    return edl.locataireCode!;
  }

  /// Vérifie le code fourni et finalise l'EDL si correct.
  Future<void> signAsLocataire(EtatDesLieux edl, String inputCode) async {
    if (edl.status != EtatDesLieuxStatus.enAttenteSignatureLocataire) {
      throw EtatDesLieuxException(
        'Cet EDL n\'est pas en attente de signature locataire.',
      );
    }
    if (edl.locataireCode == null ||
        edl.locataireCode!.toUpperCase() != inputCode.trim().toUpperCase()) {
      throw EtatDesLieuxException('Code invalide.');
    }
    edl.locataireSignatureAt = DateTime.now().toUtc();
    edl.status = EtatDesLieuxStatus.finalise;
    edl.updatedAt = DateTime.now().toUtc();
    // Calcul final du hash d'intégrité — fige le document.
    edl.integrityHash = edl.computeIntegrityHash();
    await LocalDatabase.etatDesLieuxBox.put(edl.id, edl);
    notifyListeners();
  }

  /// Abandonne le processus de signature (code perdu, erreur) avant finalisation.
  Future<void> revertToDraft(EtatDesLieux edl) async {
    if (edl.isFinalized) {
      throw EtatDesLieuxException('Impossible : EDL finalisé.');
    }
    edl.status = EtatDesLieuxStatus.brouillon;
    edl.proprietaireSignaturePng = null;
    edl.proprietaireSignatureAt = null;
    edl.locataireCode = null;
    edl.updatedAt = DateTime.now().toUtc();
    await LocalDatabase.etatDesLieuxBox.put(edl.id, edl);
    notifyListeners();
  }

  Future<void> delete(String id) async {
    final edl = byId(id);
    if (edl == null) return;
    if (edl.isFinalized) {
      throw EtatDesLieuxException(
        'Impossible de supprimer un EDL finalisé.',
      );
    }
    await PhotoStorage.deleteAllForEtat(id);
    await LocalDatabase.etatDesLieuxBox.delete(id);
    notifyListeners();
  }

  static const _codeAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  static String _generateCode({int length = 6}) {
    final rng = Random.secure();
    return List.generate(length, (_) => _codeAlphabet[rng.nextInt(_codeAlphabet.length)])
        .join();
  }

  int get count => LocalDatabase.etatDesLieuxBox.length;
}
