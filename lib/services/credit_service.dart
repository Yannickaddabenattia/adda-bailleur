import 'package:flutter/foundation.dart';

import '../core/storage/local_database.dart';
import '../models/credit_immobilier.dart';

class CreditService extends ChangeNotifier {
  List<CreditImmobilier> get all {
    final items = LocalDatabase.creditsImmobiliersBox.values.toList();
    items.sort((a, b) => b.dateDebut.compareTo(a.dateDebut));
    return items;
  }

  CreditImmobilier? byId(String id) =>
      LocalDatabase.creditsImmobiliersBox.get(id);

  List<CreditImmobilier> forLogement(String logementId) =>
      all.where((c) => c.logementId == logementId).toList();

  /// Total des mensualités annuelles (assurance comprise) pour un logement
  /// sur une année donnée. Ne compte que les mois où le crédit est actif.
  /// Bascule sur la mensualité du rachat à partir de `dateRachat`.
  double annualPaymentsForLogement(String logementId, int year) {
    var total = 0.0;
    for (final c in forLogement(logementId)) {
      for (var m = 1; m <= 12; m++) {
        final date = DateTime(year, m, 1);
        if (date.isBefore(DateTime(c.dateDebut.year, c.dateDebut.month, 1))) {
          continue;
        }
        if (date.isAfter(c.dateFin)) continue;
        total += c.mensualiteTotaleA(date);
      }
    }
    return total;
  }

  /// Mensualités totales d'un logement par mois pour une année donnée.
  Map<int, double> monthlyPayments(String logementId, int year) {
    final out = <int, double>{};
    for (var m = 1; m <= 12; m++) {
      out[m] = 0;
    }
    for (final c in forLogement(logementId)) {
      for (var m = 1; m <= 12; m++) {
        final date = DateTime(year, m, 1);
        if (date.isBefore(DateTime(c.dateDebut.year, c.dateDebut.month, 1))) {
          continue;
        }
        if (date.isAfter(c.dateFin)) continue;
        out[m] = (out[m] ?? 0) + c.mensualiteTotaleA(date);
      }
    }
    return out;
  }

  List<CreditImmobilier> byStatut(StatutCredit statut) =>
      all.where((c) => c.statut == statut).toList();

  /// Total des **intérêts** (déductibles fiscalement) payés sur un crédit
  /// pour une année donnée. Calcul échéance par échéance avec rachat pris
  /// en compte. Ne compte pas le capital ni l'assurance.
  double interetsForCreditYear(CreditImmobilier c, int year) {
    var total = 0.0;
    for (final e in c.echeances()) {
      if (e.year != year) continue;
      total += c.decomposerMois(e).interets;
    }
    return total;
  }

  /// Total assurance d'un crédit pour une année (mois actifs).
  double assuranceForCreditYear(CreditImmobilier c, int year) {
    var total = 0.0;
    for (final e in c.echeances()) {
      if (e.year != year) continue;
      total += c.decomposerMois(e).assurance;
    }
    return total;
  }

  /// Somme des intérêts pour tous les crédits d'un logement sur une année.
  double interetsForLogementYear(String logementId, int year) {
    var total = 0.0;
    for (final c in forLogement(logementId)) {
      total += interetsForCreditYear(c, year);
    }
    return total;
  }

  /// Somme des assurances pour tous les crédits d'un logement sur une année.
  double assuranceForLogementYear(String logementId, int year) {
    var total = 0.0;
    for (final c in forLogement(logementId)) {
      total += assuranceForCreditYear(c, year);
    }
    return total;
  }

  Future<CreditImmobilier> add(CreditImmobilier c) async {
    await LocalDatabase.creditsImmobiliersBox.put(c.id, c);
    notifyListeners();
    return c;
  }

  Future<CreditImmobilier> update(CreditImmobilier c) async {
    c.integrityHash = c.computeIntegrityHash();
    await LocalDatabase.creditsImmobiliersBox.put(c.id, c);
    notifyListeners();
    return c;
  }

  Future<void> delete(String id) async {
    await LocalDatabase.creditsImmobiliersBox.delete(id);
    notifyListeners();
  }

  int get count => LocalDatabase.creditsImmobiliersBox.length;
}
