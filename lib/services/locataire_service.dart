import 'package:flutter/foundation.dart';

import '../core/storage/local_database.dart';
import '../models/locataire.dart';

class LocataireService extends ChangeNotifier {
  List<Locataire> get all {
    final items = LocalDatabase.locatairesBox.values.toList();
    items.sort((a, b) =>
        '${a.lastName} ${a.firstName}'.toLowerCase().compareTo(
              '${b.lastName} ${b.firstName}'.toLowerCase(),
            ));
    return items;
  }

  Locataire? byId(String id) => LocalDatabase.locatairesBox.get(id);

  List<Locataire> byLogement(String logementId) {
    return all.where((l) => l.logementIds.contains(logementId)).toList();
  }

  List<Locataire> get actuels => all.where((l) => !l.isArchived).toList();

  List<Locataire> get anciens {
    final list = all.where((l) => l.isArchived).toList()
      ..sort((a, b) => (b.dateSortie ?? b.createdAt)
          .compareTo(a.dateSortie ?? a.createdAt));
    return list;
  }

  List<Locataire> get futurs => all.where((l) => l.isFutur).toList();

  Future<Locataire> add(Locataire locataire) async {
    await LocalDatabase.locatairesBox.put(locataire.id, locataire);
    notifyListeners();
    return locataire;
  }

  Future<Locataire> update(Locataire locataire) async {
    locataire.updatedAt = DateTime.now().toUtc();
    await LocalDatabase.locatairesBox.put(locataire.id, locataire);
    notifyListeners();
    return locataire;
  }

  Future<void> delete(String id) async {
    await LocalDatabase.locatairesBox.delete(id);
    notifyListeners();
  }

  Future<void> assignToLogement(String locataireId, String logementId) async {
    final locataire = byId(locataireId);
    if (locataire == null) return;
    if (!locataire.logementIds.contains(logementId)) {
      locataire.logementIds.add(logementId);
      await update(locataire);
    }
  }

  Future<void> unassignFromLogement(String locataireId, String logementId) async {
    final locataire = byId(locataireId);
    if (locataire == null) return;
    locataire.logementIds.remove(logementId);
    await update(locataire);
  }

  int get count => LocalDatabase.locatairesBox.length;
}
