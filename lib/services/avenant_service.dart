import 'package:flutter/foundation.dart';

import '../core/storage/local_database.dart';
import '../models/avenant.dart';

class AvenantService extends ChangeNotifier {
  List<Avenant> get all {
    final items = LocalDatabase.avenantsBox.values.toList();
    items.sort((a, b) => b.dateEffet.compareTo(a.dateEffet));
    return items;
  }

  Avenant? byId(String? id) {
    if (id == null) return null;
    return LocalDatabase.avenantsBox.get(id);
  }

  /// Avenants liés à un contrat de bail donné, triés du plus récent
  /// (numéro le plus élevé) au plus ancien.
  List<Avenant> forContrat(String contratBailId) {
    final items = all.where((a) => a.contratBailId == contratBailId).toList();
    items.sort((a, b) => b.numero.compareTo(a.numero));
    return items;
  }

  /// Prochain numéro à attribuer pour un nouvel avenant d'un contrat.
  int nextNumeroFor(String contratBailId) {
    final existing = forContrat(contratBailId);
    if (existing.isEmpty) return 1;
    return existing.first.numero + 1;
  }

  Future<Avenant> save(Avenant a) async {
    a.updatedAt = DateTime.now().toUtc();
    await LocalDatabase.avenantsBox.put(a.id, a);
    notifyListeners();
    return a;
  }

  Future<void> delete(String id) async {
    await LocalDatabase.avenantsBox.delete(id);
    notifyListeners();
  }
}
