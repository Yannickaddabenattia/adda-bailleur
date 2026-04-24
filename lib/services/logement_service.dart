import 'package:flutter/foundation.dart';

import '../core/storage/local_database.dart';
import '../models/logement.dart';

class LogementService extends ChangeNotifier {
  List<Logement> get all {
    final items = LocalDatabase.logementsBox.values.toList();
    items.sort((a, b) => a.libelle.toLowerCase().compareTo(b.libelle.toLowerCase()));
    return items;
  }

  Logement? byId(String id) => LocalDatabase.logementsBox.get(id);

  Future<Logement> add(Logement logement) async {
    await LocalDatabase.logementsBox.put(logement.id, logement);
    notifyListeners();
    return logement;
  }

  Future<Logement> update(Logement logement) async {
    logement.updatedAt = DateTime.now().toUtc();
    await LocalDatabase.logementsBox.put(logement.id, logement);
    notifyListeners();
    return logement;
  }

  Future<void> delete(String id) async {
    await LocalDatabase.logementsBox.delete(id);
    notifyListeners();
  }

  int get count => LocalDatabase.logementsBox.length;
}
