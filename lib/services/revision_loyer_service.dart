import 'package:flutter/foundation.dart';

import '../core/storage/local_database.dart';
import '../models/logement.dart';
import '../models/revision_loyer.dart';

/// Représente un loyer effectif (HC + charges) à une date donnée.
class LoyerEffectif {
  final double loyerHC;
  final double charges;
  const LoyerEffectif({required this.loyerHC, required this.charges});
  double get total => loyerHC + charges;
}

class RevisionLoyerService extends ChangeNotifier {
  /// Toutes les révisions, triées de la plus récente à la plus ancienne
  /// (par date d'effet).
  List<RevisionLoyer> get all {
    final items = LocalDatabase.revisionsLoyerBox.values.toList();
    items.sort((a, b) => b.dateEffet.compareTo(a.dateEffet));
    return items;
  }

  RevisionLoyer? byId(String id) =>
      LocalDatabase.revisionsLoyerBox.get(id);

  /// Révisions d'un logement, triées chronologiquement (plus récente d'abord).
  List<RevisionLoyer> forLogement(String logementId) =>
      all.where((r) => r.logementId == logementId).toList();

  /// Loyer effectif pour [logement] au [date] donné.
  ///
  /// Recherche la révision la plus récente dont la `dateEffet` est <= [date].
  /// Si aucune révision n'est applicable (date antérieure à toutes les
  /// révisions ou aucune révision saisie), retourne le loyer de base du
  /// logement.
  LoyerEffectif loyerEffectifAt({
    required Logement logement,
    required DateTime date,
  }) {
    final revisions = forLogement(logement.id)
      ..sort((a, b) => b.dateEffet.compareTo(a.dateEffet));
    final monthStart = DateTime(date.year, date.month, 1);
    for (final r in revisions) {
      if (!r.dateEffet.isAfter(monthStart)) {
        return LoyerEffectif(loyerHC: r.loyerHC, charges: r.charges);
      }
    }
    return LoyerEffectif(
      loyerHC: logement.loyerHC,
      charges: logement.charges,
    );
  }

  Future<RevisionLoyer> add(RevisionLoyer r) async {
    await LocalDatabase.revisionsLoyerBox.put(r.id, r);
    notifyListeners();
    return r;
  }

  Future<RevisionLoyer> update(RevisionLoyer r) async {
    r.integrityHash = r.computeIntegrityHash();
    await LocalDatabase.revisionsLoyerBox.put(r.id, r);
    notifyListeners();
    return r;
  }

  Future<void> delete(String id) async {
    await LocalDatabase.revisionsLoyerBox.delete(id);
    notifyListeners();
  }

  int get count => LocalDatabase.revisionsLoyerBox.length;
}
