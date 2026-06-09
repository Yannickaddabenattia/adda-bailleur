import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/storage/local_database.dart';
import '../models/logement.dart';
import '../models/sci.dart';
import 'credit_service.dart';
import 'depense_service.dart';
import 'logement_service.dart';
import 'quittance_service.dart';

/// Barème de l'IS (impôt sur les sociétés) 2024+ pour les PME éligibles
/// au taux réduit (CA < 10 M€, capital intégralement libéré et détenu à
/// 75 % par personnes physiques) — ce qui couvre la quasi-totalité des
/// SCI à l'IS.
class BaremeIS2026 {
  /// Taux réduit appliqué jusqu'à 42 500 € de bénéfice.
  static const double tauxReduit = 0.15;

  /// Plafond du taux réduit (en €).
  static const double seuilTauxReduit = 42500;

  /// Taux normal au-delà.
  static const double tauxNormal = 0.25;

  /// Calcule l'IS sur un bénéfice donné (en €) en appliquant les deux taux.
  static double calculer(double benefice) {
    if (benefice <= 0) return 0;
    if (benefice <= seuilTauxReduit) return benefice * tauxReduit;
    return seuilTauxReduit * tauxReduit +
        (benefice - seuilTauxReduit) * tauxNormal;
  }
}

/// Détail du calcul fiscal d'une SCI à l'IS pour une année.
class CalculSCIIS {
  final SCI sci;
  final int annee;
  final double recettes;
  final double charges;
  final double interets;
  final double amortissements;
  final double benefice;
  final double impotIS;
  final double distribution;
  final double prelevementForfaitaireUnique; // PFU 30 % sur distribution

  const CalculSCIIS({
    required this.sci,
    required this.annee,
    required this.recettes,
    required this.charges,
    required this.interets,
    required this.amortissements,
    required this.benefice,
    required this.impotIS,
    required this.distribution,
    required this.prelevementForfaitaireUnique,
  });

  /// Total dû par le foyer en lien avec cette SCI (IS payé par la SCI + PFU
  /// payé par les associés sur les dividendes).
  double get totalCoutFiscal => impotIS + prelevementForfaitaireUnique;
}

/// Service de gestion des SCI et de leur calcul fiscal (IS uniquement).
/// Les SCI à l'IR sont traitées par `FiscaliteService` comme des biens
/// transparents (intégrées au foyer fiscal personnel).
class SCIService extends ChangeNotifier {
  /// Taux global du Prélèvement Forfaitaire Unique sur dividendes SCI-IS.
  /// - Jusqu'en 2025 : 30 % (12,8 % IR + 17,2 % PS).
  /// - Dès 2026 : 31,4 % (12,8 % IR + 18,6 % PS, LFSS 2026 — hausse CSG
  ///   « contribution autonomie »).
  static double tauxPFUPour(int year) {
    if (year < 2026) return 0.30;
    return 0.314;
  }

  /// Alias rétro-compatible. À éviter pour les nouveaux calculs.
  @Deprecated('Utiliser tauxPFUPour(year) pour gérer le multi-années')
  static const double tauxPFU = 0.30;

  final LogementService _logementService;
  final QuittanceService _quittanceService;
  final DepenseService _depenseService;
  final CreditService _creditService;

  SCIService(
    this._logementService,
    this._quittanceService,
    this._depenseService,
    this._creditService,
  );

  List<SCI> get all {
    final items = LocalDatabase.scisBox.values.toList();
    items.sort(
        (a, b) => a.nom.toLowerCase().compareTo(b.nom.toLowerCase()));
    return items;
  }

  SCI? byId(String? id) {
    if (id == null) return null;
    return LocalDatabase.scisBox.get(id);
  }

  Future<SCI> add(SCI sci) async {
    await LocalDatabase.scisBox.put(sci.id, sci);
    notifyListeners();
    return sci;
  }

  Future<SCI> update(SCI sci) async {
    sci.updatedAt = DateTime.now().toUtc();
    await LocalDatabase.scisBox.put(sci.id, sci);
    notifyListeners();
    return sci;
  }

  Future<void> delete(String id) async {
    await LocalDatabase.scisBox.delete(id);
    // Détacher les logements qui pointaient vers cette SCI.
    for (final l in _logementService.all.where((l) => l.sciId == id)) {
      l.sciId = null;
      await _logementService.update(l);
    }
    notifyListeners();
  }

  /// Logements rattachés à une SCI donnée.
  List<Logement> logementsForSci(String sciId) =>
      _logementService.all.where((l) => l.sciId == sciId).toList();

  /// Calcul fiscal annuel d'une SCI à l'IS.
  ///
  /// Bénéfice fiscal = recettes − charges déductibles − intérêts d'emprunt
  /// − amortissements déclarés (champ libre `Logement.amortissementAnnuel`).
  ///
  /// IS = bénéfice × 15 % jusqu'à 42 500 €, puis × 25 %.
  ///
  /// La distribution de dividendes saisie par l'utilisateur est soumise au
  /// PFU. Taux par année : jusqu'en 2025 → 30 % (12,8 % IR + 17,2 % PS) ;
  /// dès 2026 → 31,4 % (12,8 % IR + 18,6 % PS, LFSS 2026).
  ///
  /// Retourne `null` si la SCI est à l'IR (ce service ne calcule que l'IS ;
  /// les SCI-IR sont traitées par `FiscaliteService`).
  CalculSCIIS? calculerIS(SCI sci, int year) {
    if (sci.regimeForYear(year) != SCIRegime.is_) return null;
    final logements = logementsForSci(sci.id);

    var recettes = 0.0;
    var charges = 0.0;
    var interets = 0.0;
    var amortissements = 0.0;

    for (final l in logements) {
      recettes += _quittanceService.all
          .where((q) => q.logementId == l.id && q.periodYear == year)
          .fold<double>(0, (s, q) => s + q.total);
      charges += _depenseService
          .forLogement(l.id)
          .where((d) => d.date.year == year)
          .fold<double>(0, (s, d) => s + d.montant);
      interets += _creditService.interetsForLogementYear(l.id, year);
      amortissements += l.amortissementAnnuel;
    }

    final benefice = math.max(0.0, recettes - charges - interets - amortissements);
    final impotIS = BaremeIS2026.calculer(benefice);

    final distribution = sci.distributionPourAnnee(year);
    final pfu = distribution * tauxPFUPour(year);

    return CalculSCIIS(
      sci: sci,
      annee: year,
      recettes: recettes,
      charges: charges,
      interets: interets,
      amortissements: amortissements,
      benefice: benefice,
      impotIS: impotIS,
      distribution: distribution,
      prelevementForfaitaireUnique: pfu,
    );
  }

  /// Somme des IS + PFU dus pour toutes les SCI à l'IS sur [year].
  /// C'est ce montant qu'on intègre au tableau de bord finance.
  double totalCoutFiscalIS(int year) {
    var total = 0.0;
    for (final sci in all
        .where((s) => s.regimeForYear(year) == SCIRegime.is_)) {
      final c = calculerIS(sci, year);
      if (c != null) total += c.totalCoutFiscal;
    }
    return total;
  }
}
