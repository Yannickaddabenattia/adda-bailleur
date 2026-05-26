import 'package:flutter/foundation.dart';

import '../core/storage/local_database.dart';
import '../models/quittance.dart';

class QuittanceService extends ChangeNotifier {
  List<Quittance> get all {
    final items = LocalDatabase.quittancesBox.values.toList();
    items.sort((a, b) {
      final c = b.periodYear.compareTo(a.periodYear);
      if (c != 0) return c;
      return b.periodMonth.compareTo(a.periodMonth);
    });
    return items;
  }

  Quittance? byId(String id) => LocalDatabase.quittancesBox.get(id);

  List<Quittance> forLogement(String logementId) =>
      all.where((q) => q.logementId == logementId).toList();

  List<Quittance> forLocataire(String locataireId) =>
      all.where((q) => q.locataireId == locataireId).toList();

  /// Vérifie qu'une quittance n'existe pas déjà pour ce locataire/période.
  bool exists({
    required String locataireId,
    required int year,
    required int month,
  }) {
    return all.any((q) =>
        q.locataireId == locataireId &&
        q.periodYear == year &&
        q.periodMonth == month);
  }

  Future<Quittance> add(Quittance q) async {
    await LocalDatabase.quittancesBox.put(q.id, q);
    notifyListeners();
    return q;
  }

  /// Remplace une quittance existante par sa version modifiée.
  /// Le hash d'intégrité doit déjà être à jour (utiliser `Quittance.edit`).
  Future<Quittance> update(Quittance q) async {
    await LocalDatabase.quittancesBox.put(q.id, q);
    notifyListeners();
    return q;
  }

  Future<void> delete(String id) async {
    await LocalDatabase.quittancesBox.delete(id);
    notifyListeners();
  }

  int get count => LocalDatabase.quittancesBox.length;
}
