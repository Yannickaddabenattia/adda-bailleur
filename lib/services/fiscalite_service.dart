import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/storage/local_database.dart';
import '../models/depense.dart';
import '../models/fiscal_settings.dart';
import '../models/logement.dart';
import '../models/sci.dart';
import 'credit_service.dart';
import 'depense_service.dart';
import 'logement_service.dart';
import 'quittance_service.dart';

/// Barème de l'impôt sur le revenu — millésime 2026 (revenus 2025).
/// Tranches en euros par part fiscale.
class BaremeIR2026 {
  static const int annee = 2026;

  /// (limite supérieure de la tranche, taux). La dernière utilise +infini.
  static const List<(double, double)> tranches = [
    (11497, 0.00),
    (29315, 0.11),
    (83823, 0.30),
    (180294, 0.41),
    (double.infinity, 0.45),
  ];

  /// Plafond de l'avantage du quotient familial : 1 759 € par demi-part
  /// supplémentaire (revenus 2025, déclaration 2026).
  static const double plafondQuotientFamilialDemiPart = 1759;

  /// Taux des prélèvements sociaux sur les revenus fonciers.
  static const double tauxPrelevementsSociaux = 0.172;

  /// Plafond du déficit foncier imputable sur le revenu global.
  static const double plafondDeficitImputableGlobal = 10700;

  /// Plafond global des niches fiscales (par foyer, par an).
  static const double plafondGlobalNichesFiscales = 10000;

  /// Micro-foncier (location nue) : seuil de recettes brutes du foyer.
  /// Au-delà → régime réel obligatoire.
  static const double seuilMicroFoncier = 15000;

  /// Abattement forfaitaire micro-foncier (30 %).
  static const double abattementMicroFoncier = 0.30;

  /// Micro-BIC (LMNP location meublée non pro) : seuil annuel.
  /// Au-delà → BIC réel obligatoire.
  static const double seuilMicroBIC = 77700;

  /// Abattement forfaitaire micro-BIC location meublée classique (50 %).
  static const double abattementMicroBIC = 0.50;

  /// Plafond du prix de revient Pinel/Denormandie (somme des biens).
  static const double plafondPrixRevient = 300000;

  /// Plafond Pinel/Denormandie par m² de surface habitable.
  static const double plafondPrixRevientParM2 = 5500;

  /// Taux de réduction Pinel selon l'année d'acquisition et la durée
  /// d'engagement (6, 9 ou 12 ans).
  ///
  /// Pinel classique 2014-2022 : 12 / 18 / 21 %
  /// Pinel+ 2023            : 10,5 / 15 / 17,5 %
  /// Pinel 2023 (classique) :  9 / 12 / 14 %
  /// Pinel+ 2024            :  9 / 12 / 14 %
  /// Pinel 2024 (classique) :  6 /  9 / 10,5 %
  /// Le taux total est réparti linéairement sur la durée d'engagement.
  static double tauxPinelTotal({
    required int anneeAcquisition,
    required int dureeAnnees,
    required bool pinelPlus,
  }) {
    if (dureeAnnees != 6 && dureeAnnees != 9 && dureeAnnees != 12) return 0;
    if (anneeAcquisition <= 2022) {
      switch (dureeAnnees) {
        case 6:
          return 0.12;
        case 9:
          return 0.18;
        case 12:
          return 0.21;
      }
    } else if (anneeAcquisition == 2023) {
      if (pinelPlus) {
        switch (dureeAnnees) {
          case 6:
            return 0.105;
          case 9:
            return 0.15;
          case 12:
            return 0.175;
        }
      }
      switch (dureeAnnees) {
        case 6:
          return 0.09;
        case 9:
          return 0.12;
        case 12:
          return 0.14;
      }
    } else if (anneeAcquisition == 2024) {
      if (pinelPlus) {
        switch (dureeAnnees) {
          case 6:
            return 0.09;
          case 9:
            return 0.12;
          case 12:
            return 0.14;
        }
      }
      switch (dureeAnnees) {
        case 6:
          return 0.06;
        case 9:
          return 0.09;
        case 12:
          return 0.105;
      }
    }
    return 0; // hors fenêtre Pinel (≥ 2025)
  }

  /// Taux Denormandie : aligné sur le Pinel classique de la même année.
  /// Disponible 2019-2027 sur l'ancien rénové.
  static double tauxDenormandieTotal({
    required int anneeAcquisition,
    required int dureeAnnees,
  }) {
    if (anneeAcquisition < 2019 || anneeAcquisition > 2027) return 0;
    return tauxPinelTotal(
      anneeAcquisition: anneeAcquisition <= 2022 ? 2022 : anneeAcquisition,
      dureeAnnees: dureeAnnees,
      pinelPlus: false,
    );
  }

  /// Calcule l'IR sur un revenu net imposable donné, à parts = 1.
  static double impotPourUnePart(double revenuParPart) {
    if (revenuParPart <= 0) return 0;
    var impot = 0.0;
    var precedent = 0.0;
    for (final (limite, taux) in tranches) {
      final dans = math.min(revenuParPart, limite) - precedent;
      if (dans <= 0) break;
      impot += dans * taux;
      precedent = limite;
      if (revenuParPart <= limite) break;
    }
    return impot;
  }
}

/// Réduction d'impôt apportée par un dispositif (Pinel, Denormandie…).
class ReductionDispositif {
  final Logement logement;
  final DispositifFiscal dispositif;
  final int anneeAcquisition;
  final int dureeAnnees;
  final double prixRevientPlafonne;
  final double tauxTotal;
  final double reductionAnnuelle;
  final bool dansLaFenetre;

  ReductionDispositif({
    required this.logement,
    required this.dispositif,
    required this.anneeAcquisition,
    required this.dureeAnnees,
    required this.prixRevientPlafonne,
    required this.tauxTotal,
    required this.reductionAnnuelle,
    required this.dansLaFenetre,
  });
}

/// Détail fiscal d'un logement pour une année.
class DetailFiscalLogement {
  final Logement logement;
  /// Recettes brutes réelles (loyers + charges encaissés via quittances)
  /// AVANT l'éventuel abattement Borloo.
  final double recettesBrutes;
  /// Taux d'abattement Borloo appliqué (0 si pas de Borloo en vigueur).
  final double tauxAbattementBorloo;
  final double charges; // déductibles, hors intérêts/assurance crédit
  final double interets;
  final double assuranceCredit;

  DetailFiscalLogement({
    required this.logement,
    required this.recettesBrutes,
    required this.charges,
    required this.interets,
    required this.assuranceCredit,
    this.tauxAbattementBorloo = 0,
  });

  /// Montant en € de l'abattement Borloo (≥ 0).
  double get abattementBorloo => recettesBrutes * tauxAbattementBorloo;

  /// Recettes imposables = recettes brutes − abattement Borloo.
  double get recettesImposables => recettesBrutes - abattementBorloo;

  double get totalChargesDeductibles => charges + interets + assuranceCredit;
  double get revenuNet => recettesImposables - totalChargesDeductibles;
  double get revenuAvantInterets =>
      recettesImposables - charges - assuranceCredit;
  bool get enDeficit => revenuNet < 0;
}

/// Résultat global d'un calcul fiscal pour une année.
class CalculFiscalAnnuel {
  final int annee;
  final List<DetailFiscalLogement> details;
  final double revenuFoncierBrut;
  final double chargesTotales;
  final double interetsTotaux;
  final double assuranceTotale;

  /// Somme des nets par logement (positifs et négatifs).
  final double revenuFoncierNetAvantImputation;

  /// Déficit imputable sur le revenu global (max 10 700 €).
  final double deficitImputableGlobal;

  /// Déficit reportable sur les revenus fonciers des 10 années suivantes.
  final double deficitReportableFoncier;

  /// Reportables des années précédentes consommés cette année.
  final double reportablesConsommes;

  /// Revenu foncier net imposable (≥ 0) après imputation des reportables.
  final double revenuFoncierImposable;

  /// Prélèvements sociaux 17,2 % sur revenu foncier imposable.
  final double prelevementsSociaux;

  /// IR sans le revenu foncier (référence, pour calcul incrémental).
  final double impotSansFoncier;

  /// IR avec le revenu foncier (avec quotient familial + plafonnement).
  final double impotAvecFoncier;

  /// Impôt additionnel attribuable aux revenus fonciers.
  double get impotAdditionnelFoncier =>
      math.max(0, impotAvecFoncier - impotSansFoncier);

  double get totalImpotFoncier =>
      impotAdditionnelFoncier + prelevementsSociaux;

  /// Bénéfice net après impôt.
  double get beneficeNet =>
      revenuFoncierNetAvantImputation - totalImpotFoncier;

  /// Tranche marginale d'imposition appliquée (informatif).
  final double tmiApplique;

  /// Réductions par bien (Pinel/Denormandie).
  final List<ReductionDispositif> reductions;

  /// Réduction totale brute (avant plafonnement niches).
  final double reductionBrute;

  /// Réduction effectivement déduite après plafonnement global des niches
  /// (10 000 € — autres niches du foyer).
  final double reductionAppliquee;

  /// Plafond restant disponible (10 000 € − autres niches).
  final double plafondRestant;

  /// Régime appliqué pour les logements en location nue (micro-foncier ou
  /// réel), déterminé automatiquement selon le seuil de 15 000 € et la
  /// présence de dispositifs Pinel/Denormandie.
  final RegimeFiscal regimeNuApplique;

  /// Recettes brutes totales des logements en LMNP (location meublée non pro).
  final double recettesLmnpBrutes;

  /// Revenu LMNP imposable après abattement micro-BIC 50 %.
  final double revenuLmnpImposable;

  /// `true` si les recettes LMNP dépassent 77 700 € (basculement obligatoire
  /// vers le BIC réel, non géré ici).
  final bool lmnpDepasseSeuilMicroBIC;

  CalculFiscalAnnuel({
    required this.annee,
    required this.details,
    required this.revenuFoncierBrut,
    required this.chargesTotales,
    required this.interetsTotaux,
    required this.assuranceTotale,
    required this.revenuFoncierNetAvantImputation,
    required this.deficitImputableGlobal,
    required this.deficitReportableFoncier,
    required this.reportablesConsommes,
    required this.revenuFoncierImposable,
    required this.prelevementsSociaux,
    required this.impotSansFoncier,
    required this.impotAvecFoncier,
    required this.tmiApplique,
    this.reductions = const [],
    this.reductionBrute = 0,
    this.reductionAppliquee = 0,
    this.plafondRestant = BaremeIR2026.plafondGlobalNichesFiscales,
    this.regimeNuApplique = RegimeFiscal.reel,
    this.recettesLmnpBrutes = 0,
    this.revenuLmnpImposable = 0,
    this.lmnpDepasseSeuilMicroBIC = false,
  });

  /// Impôt additionnel net après réduction Pinel/Denormandie.
  double get impotAdditionnelFoncierNet =>
      math.max(0, impotAdditionnelFoncier - reductionAppliquee);

  /// Total à payer = IR additionnel net + PS.
  double get totalImpotFoncierNet =>
      impotAdditionnelFoncierNet + prelevementsSociaux;

  /// IR total du foyer (foncier + autres revenus) après réductions.
  double get impotRevenuFoyerNet =>
      math.max(0, impotAvecFoncier - reductionAppliquee);

  /// Total à payer du foyer = IR total net + prélèvements sociaux fonciers.
  double get totalImpotFoyer =>
      impotRevenuFoyerNet + prelevementsSociaux;
}

/// Service de calcul fiscal pour les revenus fonciers.
///
/// Phase 1 : location nue au régime réel + barème progressif IR + PS 17,2 %
/// + déficit foncier (imputable / reportable).
/// Hors périmètre phase 1 : LMNP réel + amortissement, Pinel/Denormandie,
/// micro-foncier (mais structure prête pour extension).
class FiscaliteService extends ChangeNotifier {
  final LogementService _logementService;
  final QuittanceService _quittanceService;
  final DepenseService _depenseService;
  final CreditService _creditService;

  static const String _settingsBoxKey = 'fiscal_settings';

  FiscaliteService({
    required LogementService logementService,
    required QuittanceService quittanceService,
    required DepenseService depenseService,
    required CreditService creditService,
  })  : _logementService = logementService,
        _quittanceService = quittanceService,
        _depenseService = depenseService,
        _creditService = creditService;

  // ---- Settings ----

  FiscalSettings get settings {
    final box = LocalDatabase.fiscalSettingsBox;
    return box.get(_settingsBoxKey) ?? FiscalSettings();
  }

  Future<void> saveSettings(FiscalSettings s) async {
    await LocalDatabase.fiscalSettingsBox.put(_settingsBoxKey, s);
    notifyListeners();
  }

  // ---- Calculs ----

  /// Recettes brutes (loyers + charges encaissées) pour un logement et une année.
  double recettesBrutesLogement(String logementId, int year) {
    return _quittanceService.all
        .where((q) => q.logementId == logementId && q.periodYear == year)
        .fold<double>(0, (s, q) => s + q.total);
  }

  /// Charges déductibles (hors crédit) : on prend toutes les dépenses
  /// SAUF la catégorie « Crédit immobilier » (les intérêts viennent du
  /// service crédit pour éviter la double comptabilisation).
  double chargesDeductiblesLogement(String logementId, int year) {
    return _depenseService
        .forLogement(logementId)
        .where((d) =>
            d.date.year == year && d.categorie != ExpenseCategories.credit)
        .fold<double>(0, (s, d) => s + d.montant);
  }

  /// Calcule la réduction Pinel/Denormandie annuelle pour un logement.
  /// Retourne `null` si pas de dispositif applicable cette année, ou si le
  /// dispositif n'ouvre pas droit à réduction (cas Borloo : abattement sur
  /// recettes, géré séparément dans le calcul foncier).
  ReductionDispositif? reductionPourLogement(Logement l, int year) {
    if (!l.dispositif.isPinelDenormandie) return null;
    if (l.dateAcquisition == null) return null;
    final anneeAcq = l.dateAcquisition!.year;
    final dureeMax = l.dureeEngagementAnnees;
    final finEngagement = anneeAcq + dureeMax;
    // Fenêtre par défaut = acquisition + durée d'engagement. Si
    // l'utilisateur a renseigné des dates personnalisées sur le logement,
    // on les croise avec la fenêtre par défaut (intersection).
    var dansLaFenetre = year >= anneeAcq && year < finEngagement;
    if (l.dateDebutDispositif != null &&
        year < l.dateDebutDispositif!.year) {
      dansLaFenetre = false;
    }
    if (l.dateFinDispositif != null &&
        year > l.dateFinDispositif!.year) {
      dansLaFenetre = false;
    }

    // Plafonnement du prix de revient.
    final plafondM2 =
        l.surface * BaremeIR2026.plafondPrixRevientParM2;
    final base = math.min(
      math.min(l.prixRevient, BaremeIR2026.plafondPrixRevient),
      plafondM2 > 0 ? plafondM2 : double.infinity,
    );

    var taux = 0.0;
    switch (l.dispositif) {
      case DispositifFiscal.pinel:
        taux = BaremeIR2026.tauxPinelTotal(
          anneeAcquisition: anneeAcq,
          dureeAnnees: dureeMax,
          pinelPlus: false,
        );
        break;
      case DispositifFiscal.pinelPlus:
        taux = BaremeIR2026.tauxPinelTotal(
          anneeAcquisition: anneeAcq,
          dureeAnnees: dureeMax,
          pinelPlus: true,
        );
        break;
      case DispositifFiscal.denormandie:
        taux = BaremeIR2026.tauxDenormandieTotal(
          anneeAcquisition: anneeAcq,
          dureeAnnees: dureeMax,
        );
        break;
      case DispositifFiscal.aucun:
      case DispositifFiscal.borlooAncienIntermediaire:
      case DispositifFiscal.borlooAncienSocial:
      case DispositifFiscal.borlooAncienTresSocial:
        // Borloo Ancien : abattement sur recettes, pas une réduction Pinel.
        // La condition d'entrée `isPinelDenormandie` filtre déjà ces cas,
        // mais on les déclare ici pour satisfaire l'exhaustivité du switch.
        break;
    }

    final totalReduction = base * taux;
    // Étalement linéaire sur la durée d'engagement.
    final annuelle =
        dansLaFenetre && dureeMax > 0 ? totalReduction / dureeMax : 0.0;

    return ReductionDispositif(
      logement: l,
      dispositif: l.dispositif,
      anneeAcquisition: anneeAcq,
      dureeAnnees: dureeMax,
      prixRevientPlafonne: base,
      tauxTotal: taux,
      reductionAnnuelle: annuelle,
      dansLaFenetre: dansLaFenetre,
    );
  }

  /// Détermine si le foyer est éligible au micro-foncier pour [year].
  ///
  /// Conditions cumulatives (CGI art. 32) :
  /// - Recettes brutes totales du foyer ≤ 15 000 €
  /// - Aucun bien « Location nue » sous Pinel/Denormandie (ces dispositifs
  ///   imposent le régime réel)
  /// - Aucun logement détenu via SCI (même à l'IR : le micro-foncier n'est
  ///   ouvert qu'aux SCI familiales sous conditions strictes — non gérées
  ///   ici, on force le réel par sécurité)
  /// - Au moins un logement « Location nue »
  ///
  /// Hors périmètre : Monuments historiques, Malraux, loi 1948 (forcent le
  /// réel) — non gérés ici.
  bool eligibleMicroFoncier(int year) {
    final scis = _logementService.all
        .where((l) => l.statutFiscal == StatutFiscal.sci)
        .toList();
    if (scis.isNotEmpty) return false;
    final nus = _logementService.all
        .where((l) => l.statutFiscal == StatutFiscal.locationNue)
        .toList();
    if (nus.isEmpty) return false;
    // Pinel/Denormandie ouvrent droit à des charges déductibles spécifiques
    // qui imposent le réel ; Borloo Ancien applique un abattement sur recettes
    // qui exige aussi le réel.
    final aucunDispositif =
        nus.every((l) => l.dispositif == DispositifFiscal.aucun);
    if (!aucunDispositif) return false;
    final recettes = nus.fold<double>(
      0,
      (s, l) => s + recettesBrutesLogement(l.id, year),
    );
    return recettes <= BaremeIR2026.seuilMicroFoncier;
  }

  /// Régime fiscal automatiquement appliqué aux logements « Location nue »
  /// du foyer pour [year]. Auto-détecté : pas de réglage utilisateur.
  RegimeFiscal regimeNuApplique(int year) =>
      eligibleMicroFoncier(year) ? RegimeFiscal.microFoncier : RegimeFiscal.reel;

  /// Calcul fiscal complet pour une année donnée.
  ///
  /// Couvre :
  /// - Location nue au **régime réel** (calcul détaillé charges/intérêts/
  ///   déficit foncier/reportables) — appliqué si recettes > 15 000 € OU si
  ///   au moins un logement nu a un dispositif Pinel/Denormandie.
  /// - Location nue au **micro-foncier** (abattement forfaitaire 30 %, pas
  ///   de charges déductibles, pas de déficit possible) — auto-appliqué si
  ///   recettes ≤ 15 000 € et aucun dispositif.
  /// - **LMNP micro-BIC** (abattement 50 %) — appliqué à tous les logements
  ///   `StatutFiscal.lmnp`. Au-delà de 77 700 € de recettes, un flag est
  ///   levé (`lmnpDepasseSeuilMicroBIC`) mais le calcul micro-BIC continue.
  CalculFiscalAnnuel calculer(int year) {
    final s = settings;
    // Location nue ET SCI à l'IR sont traitées ensemble : la SCI à l'IR est
    // fiscalement transparente, chaque associé déclare sa quote-part comme
    // un revenu foncier classique. Les SCI à l'IS sont exclues : leur IS
    // est calculé séparément par SCIService.
    final logementsNus = _logementService.all.where((l) {
      if (l.statutFiscal == StatutFiscal.locationNue) return true;
      if (l.statutFiscal == StatutFiscal.sci) {
        final sci = LocalDatabase.scisBox.get(l.sciId);
        // SCI introuvable (orphelin) → on inclut par défaut comme nu.
        // Sinon : transparente si IR pour cette année, exclue si IS.
        return sci == null || sci.regimeForYear(year) == SCIRegime.ir;
      }
      return false;
    }).toList();
    final logementsLmnp = _logementService.all
        .where((l) => l.statutFiscal == StatutFiscal.lmnp)
        .toList();

    // ---- Régime nu : auto-détection micro vs réel ----
    final regimeNu = regimeNuApplique(year);

    final details = <DetailFiscalLogement>[];
    var sumRecettes = 0.0;
    var sumCharges = 0.0;
    var sumInterets = 0.0;
    var sumAssurance = 0.0;

    for (final l in logementsNus) {
      final recettesBrutes = recettesBrutesLogement(l.id, year);
      // Borloo Ancien : abattement spécifique sur les recettes brutes du
      // logement, avant déduction des charges. Le taux dépend du niveau de
      // convention (30/60/70 %). Appliqué uniquement si la convention est
      // en vigueur cette année-là (cf. dateDebutDispositif/dateFinDispositif).
      final borlooActif =
          l.dispositif.isBorloo && l.dispositifActifPour(year);
      final tauxAbattement =
          borlooActif ? l.dispositif.tauxAbattementBorloo : 0.0;
      final recettesImposables = recettesBrutes * (1 - tauxAbattement);
      final charges = chargesDeductiblesLogement(l.id, year);
      final interets = _creditService.interetsForLogementYear(l.id, year);
      final assurance = _creditService.assuranceForLogementYear(l.id, year);

      details.add(DetailFiscalLogement(
        logement: l,
        recettesBrutes: recettesBrutes,
        tauxAbattementBorloo: tauxAbattement,
        charges: charges,
        interets: interets,
        assuranceCredit: assurance,
      ));
      sumRecettes += recettesImposables;
      sumCharges += charges;
      sumInterets += interets;
      sumAssurance += assurance;
    }

    // ---- Calcul du revenu foncier nu imposable ----
    double netGlobal;
    double revenuFoncierImposable;
    var deficitImputableGlobal = 0.0;
    var deficitReportableFoncier = 0.0;
    var reportablesConsommes = 0.0;

    if (regimeNu == RegimeFiscal.microFoncier) {
      // Micro-foncier : 30 % d'abattement forfaitaire sur les recettes.
      // Pas de charges déductibles, pas de déficit foncier possible.
      // Les reportables des années précédentes sont gelés (non consommés).
      netGlobal = sumRecettes * (1 - BaremeIR2026.abattementMicroFoncier);
      revenuFoncierImposable = netGlobal;
    } else {
      // Régime réel : calcul détaillé avec déficit foncier (règle des
      // intérêts non imputables sur revenu global).
      netGlobal = sumRecettes - sumCharges - sumInterets - sumAssurance;

      var revenuFoncierNetSansImputation = 0.0;
      if (netGlobal < 0) {
        final x = sumRecettes - sumCharges - sumAssurance; // hors intérêts
        if (x >= 0) {
          // Tout le déficit vient des intérêts -> 100 % reportable foncier.
          deficitReportableFoncier = -netGlobal;
        } else {
          final partNonInterets = -x; // = (charges + assurance - recettes)
          final imputable = math.min(
            partNonInterets,
            BaremeIR2026.plafondDeficitImputableGlobal,
          );
          deficitImputableGlobal = imputable;
          deficitReportableFoncier =
              (partNonInterets - imputable) + sumInterets;
        }
        revenuFoncierNetSansImputation = 0;
      } else {
        revenuFoncierNetSansImputation = netGlobal;
      }

      // Consommation des reportables des années précédentes.
      final reportablesDispo = s.soldeReportableA(year);
      reportablesConsommes = math.min(
        reportablesDispo,
        revenuFoncierNetSansImputation,
      );
      revenuFoncierImposable = math.max(
        0.0,
        revenuFoncierNetSansImputation - reportablesConsommes,
      );
    }

    // ---- LMNP micro-BIC (50 % d'abattement) ----
    final recettesLmnp = logementsLmnp.fold<double>(
      0,
      (acc, l) => acc + recettesBrutesLogement(l.id, year),
    );
    final revenuLmnpImposable =
        recettesLmnp * (1 - BaremeIR2026.abattementMicroBIC);
    final lmnpDepasseSeuil = recettesLmnp > BaremeIR2026.seuilMicroBIC;

    // ---- Prélèvements sociaux (17,2 % sur foncier nu + LMNP) ----
    // Le LMNP non pro est assimilé à du patrimoine immobilier privé, donc
    // soumis aux mêmes prélèvements sociaux que les revenus fonciers.
    final assietteImmobilier = revenuFoncierImposable + revenuLmnpImposable;
    final ps = assietteImmobilier * BaremeIR2026.tauxPrelevementsSociaux;

    // ---- IR avec barème progressif + abattement 10 % sur autres revenus ----
    // Les autres revenus du foyer (salaires, pensions…) peuvent être saisis
    // année par année (utile pour suivre une carrière qui évolue). À défaut,
    // on retombe sur la valeur par défaut du foyer.
    final autresRevenusNets = s.autresRevenusBrutsPour(year) * 0.9;
    final assietteSansFoncier =
        math.max(0.0, autresRevenusNets - deficitImputableGlobal);
    final assietteAvecFoncier = math.max(
      0.0,
      autresRevenusNets + assietteImmobilier - deficitImputableGlobal,
    );

    final irSans = _impotAvecQuotientFamilial(assietteSansFoncier, s.parts);
    final irAvec = _impotAvecQuotientFamilial(assietteAvecFoncier, s.parts);

    // TMI appliqué (estimé).
    final parPart = s.parts > 0 ? assietteAvecFoncier / s.parts : 0.0;
    var tmi = 0.0;
    var prev = 0.0;
    for (final (limite, taux) in BaremeIR2026.tranches) {
      if (parPart > prev) tmi = taux;
      prev = limite;
    }

    // ---- Réductions Pinel / Denormandie ----
    // Au régime réel : pleinement applicables.
    // Au régime micro-foncier : INCOMPATIBLE (le micro exige l'absence de
    // dispositif), donc reductions = vide par construction. On laisse la
    // boucle au cas où, mais elle ne renvoie rien si on est en micro.
    final reductions = <ReductionDispositif>[];
    var reductionBrute = 0.0;
    if (regimeNu == RegimeFiscal.reel) {
      for (final l in _logementService.all) {
        final r = reductionPourLogement(l, year);
        if (r != null) {
          reductions.add(r);
          reductionBrute += r.reductionAnnuelle;
        }
      }
    }

    // Plafonnement global des niches fiscales : 10 000 € − autres niches.
    final plafondRestant = math.max(
      0.0,
      BaremeIR2026.plafondGlobalNichesFiscales - s.autresNichesFiscales,
    );
    final reductionAppliquee = math.min(reductionBrute, plafondRestant);

    return CalculFiscalAnnuel(
      annee: year,
      details: details,
      revenuFoncierBrut: sumRecettes,
      chargesTotales: sumCharges,
      interetsTotaux: sumInterets,
      assuranceTotale: sumAssurance,
      revenuFoncierNetAvantImputation: netGlobal,
      deficitImputableGlobal: deficitImputableGlobal,
      deficitReportableFoncier: deficitReportableFoncier,
      reportablesConsommes: reportablesConsommes,
      revenuFoncierImposable: revenuFoncierImposable,
      prelevementsSociaux: ps,
      impotSansFoncier: irSans,
      impotAvecFoncier: irAvec,
      tmiApplique: tmi,
      reductions: reductions,
      reductionBrute: reductionBrute,
      reductionAppliquee: reductionAppliquee,
      plafondRestant: plafondRestant,
      regimeNuApplique: regimeNu,
      recettesLmnpBrutes: recettesLmnp,
      revenuLmnpImposable: revenuLmnpImposable,
      lmnpDepasseSeuilMicroBIC: lmnpDepasseSeuil,
    );
  }

  /// IR avec quotient familial et plafonnement par demi-part.
  ///
  /// Méthode officielle : on calcule l'impôt avec le QF (assiette / parts)
  /// puis sans le QF (assiette / parts_ref où parts_ref = 1 pour célibataire,
  /// 2 pour couple). L'écart entre les deux est plafonné à
  /// 1 759 €/demi-part supplémentaire. L'impôt final est le **maximum** entre
  /// IR(quotient) et IR(parts_ref) − plafond.
  double _impotAvecQuotientFamilial(double assiette, double parts) {
    if (assiette <= 0 || parts <= 0) return 0;
    final s = settings;
    final partsRef = s.marieOuPacse ? 2.0 : 1.0;
    final partsSupp = math.max(0.0, parts - partsRef);

    // Calcul avec quotient familial complet.
    final irAvecQf =
        BaremeIR2026.impotPourUnePart(assiette / parts) * parts;

    // Calcul de référence (sans demi-parts supplémentaires).
    final irRef = BaremeIR2026.impotPourUnePart(assiette / partsRef) * partsRef;

    // Avantage du QF plafonné : 1 759 € par demi-part au-delà du couple/célib.
    final demiPartsSupp = partsSupp * 2;
    final plafondAvantage =
        demiPartsSupp * BaremeIR2026.plafondQuotientFamilialDemiPart;

    // Avantage réel apporté par les demi-parts supplémentaires.
    final avantageReel = irRef - irAvecQf;

    if (avantageReel <= plafondAvantage) {
      return irAvecQf; // Pas de plafonnement.
    }
    return irRef - plafondAvantage;
  }
}
