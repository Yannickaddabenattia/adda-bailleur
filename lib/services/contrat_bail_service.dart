import 'package:flutter/foundation.dart';

import '../core/storage/local_database.dart';
import '../models/contrat_bail.dart';

class ContratBailService extends ChangeNotifier {
  List<ContratBail> get all {
    final items = LocalDatabase.contratsBailBox.values.toList();
    items.sort((a, b) => b.dateDebut.compareTo(a.dateDebut));
    return items;
  }

  ContratBail? byId(String? id) {
    if (id == null) return null;
    return LocalDatabase.contratsBailBox.get(id);
  }

  /// Contrats rattachés à un logement.
  List<ContratBail> forLogement(String logementId) =>
      all.where((c) => c.logementId == logementId).toList();

  /// Contrats incluant un locataire donné.
  List<ContratBail> forLocataire(String locataireId) =>
      all.where((c) => c.locataireIds.contains(locataireId)).toList();

  /// Contrat en cours (dateDebut ≤ today ≤ dateFin et statut adéquat).
  ContratBail? activeForLogement(String logementId) {
    final now = DateTime.now();
    for (final c in forLogement(logementId)) {
      if (c.statut == BailStatus.termine || c.statut == BailStatus.resilie) {
        continue;
      }
      if (!now.isBefore(c.dateDebut) && !now.isAfter(c.dateFin)) {
        return c;
      }
    }
    return null;
  }

  Future<ContratBail> save(ContratBail c) async {
    c.updatedAt = DateTime.now().toUtc();
    await LocalDatabase.contratsBailBox.put(c.id, c);
    notifyListeners();
    return c;
  }

  Future<void> delete(String id) async {
    await LocalDatabase.contratsBailBox.delete(id);
    notifyListeners();
  }
}
