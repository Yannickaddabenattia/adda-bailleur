import 'package:flutter/foundation.dart';

import '../core/storage/local_database.dart';
import '../models/diagnostic.dart';

class DiagnosticService extends ChangeNotifier {
  List<Diagnostic> get all {
    final items = LocalDatabase.diagnosticsBox.values.toList();
    items.sort((a, b) => b.dateRealisation.compareTo(a.dateRealisation));
    return items;
  }

  Diagnostic? byId(String? id) {
    if (id == null) return null;
    return LocalDatabase.diagnosticsBox.get(id);
  }

  List<Diagnostic> forLogement(String logementId) =>
      all.where((d) => d.logementId == logementId).toList();

  /// Diagnostics expirés pour un logement (à renouveler).
  List<Diagnostic> expiresForLogement(String logementId) =>
      forLogement(logementId).where((d) => d.estExpire).toList();

  Future<Diagnostic> save(Diagnostic d) async {
    d.updatedAt = DateTime.now().toUtc();
    await LocalDatabase.diagnosticsBox.put(d.id, d);
    notifyListeners();
    return d;
  }

  Future<void> delete(String id) async {
    await LocalDatabase.diagnosticsBox.delete(id);
    notifyListeners();
  }
}
