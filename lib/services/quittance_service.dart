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

  /// Clé YYYY-MM pour les versements supplémentaires.
  static String moisKey(int year, int month) =>
      '$year-${month.toString().padLeft(2, '0')}';

  /// Recettes réellement encaissées pour [logementId] sur [year], ventilées
  /// par mois (1-12 ; les mois sans recette sont omis). Combine :
  /// - le loyer encaissé du mois (`montantPayePeriode` = montant réellement
  ///   payé, ou `total` à défaut), **dédoublonné par mois** : si plusieurs
  ///   quittances existent pour le même mois (une par colocataire), on garde
  ///   la plus élevée et non la somme, pour ne pas doubler le revenu ;
  /// - les versements supplémentaires (régularisations d'arriérés / avances)
  ///   alloués à un mois de [year], **sommés** — ils s'ajoutent au loyer du
  ///   mois ciblé, y compris lorsqu'ils sont saisis sur une quittance d'une
  ///   autre période.
  ///
  /// Méthode statique (pure) : même résultat pour l'accueil et le tableau de
  /// bord Finance, qui partagent ainsi une seule source de vérité.
  static Map<int, double> encaisseParMoisLogement({
    required List<Quittance> quittances,
    required String logementId,
    required int year,
  }) {
    final loyerMax = <int, double>{};
    final versements = <int, double>{};
    for (final q in quittances) {
      if (q.logementId != logementId) continue;
      if (q.periodYear == year) {
        final prev = loyerMax[q.periodMonth];
        final paye = q.montantPayePeriode;
        if (prev == null || paye > prev) loyerMax[q.periodMonth] = paye;
      }
      q.versementsSupplementaires.forEach((key, montant) {
        final parts = key.split('-');
        if (parts.length == 2 && int.tryParse(parts[0]) == year) {
          final m = int.tryParse(parts[1]);
          if (m != null && m >= 1 && m <= 12) {
            versements[m] = (versements[m] ?? 0) + montant;
          }
        }
      });
    }
    final result = <int, double>{};
    for (var m = 1; m <= 12; m++) {
      final v = (loyerMax[m] ?? 0) + (versements[m] ?? 0);
      if (v != 0) result[m] = v;
    }
    return result;
  }
}
