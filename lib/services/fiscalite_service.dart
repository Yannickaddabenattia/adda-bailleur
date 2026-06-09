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

/// Exception levée quand on demande un barème IR pour une année qu'on n'a
/// pas en base. L'appelant doit afficher un message clair à l'utilisateur,
/// surtout pas appliquer un barème par défaut.
class BaremeIRIndisponible implements Exception {
  final int annee;
  BaremeIRIndisponible(this.annee);
  @override
  String toString() => 'Barème IR indisponible pour les revenus $annee.';
}

/// Prélèvements sociaux décomposés (CSG + CRDS + prélèvement solidarité).
/// Total = csg + crds + solidarite.
class PrelevementsSociaux {
  final double csg;
  final double crds;
  final double solidarite;
  const PrelevementsSociaux({
    required this.csg,
    required this.crds,
    required this.solidarite,
  });
  double get total => csg + crds + solidarite;
}

/// Exception levée si aucun taux PS n'est défini pour l'année demandée.
class PrelevementsSociauxIndisponibles implements Exception {
  final int annee;
  const PrelevementsSociauxIndisponibles(this.annee);
  @override
  String toString() =>
      'Prélèvements sociaux indisponibles pour les revenus $annee.';
}

/// Barème de l'impôt sur le revenu, multi-années (2006-2025).
///
/// La clé est l'**année des revenus**, pas l'année de déclaration.
/// Exemple : pour des loyers perçus en 2024 (déclarés en 2025), utiliser
/// `tranchesPour(2024)`.
class BaremeIR2026 {
  /// Année du barème courant (revenus 2025, déclaration 2026).
  static const int annee = 2025;

  /// Table des barèmes par année de revenus. Chaque entrée :
  /// liste de (plafond_haut, taux), dernière tranche = +infini.
  ///
  /// Sources : Bpifrance Création / BOFiP / impots.gouv.fr.
  /// Seuils des années 2013, 2014, 2015 et 2018 reconstitués par cohérence —
  /// à confirmer sur BOFiP avant production.
  static const Map<int, List<(double, double)>> _baremes = {
    // ---- Taux 0/5,5/14/30/40 ----
    2006: [(5614, 0.00), (11198, 0.055), (24872, 0.14), (66679, 0.30),
        (double.infinity, 0.40)],
    2007: [(5687, 0.00), (11344, 0.055), (25195, 0.14), (67546, 0.30),
        (double.infinity, 0.40)],
    2008: [(5853, 0.00), (11673, 0.055), (25926, 0.14), (69505, 0.30),
        (double.infinity, 0.40)],
    2009: [(5875, 0.00), (11720, 0.055), (26030, 0.14), (69783, 0.30),
        (double.infinity, 0.40)],
    // ---- Taux max porté à 41 % ----
    2010: [(5963, 0.00), (11896, 0.055), (26420, 0.14), (70830, 0.30),
        (double.infinity, 0.41)],
    2011: [(5963, 0.00), (11896, 0.055), (26420, 0.14), (70830, 0.30),
        (double.infinity, 0.41)],
    // ---- Ajout tranche 45 % (5,5 % encore présente) ----
    2012: [(5963, 0.00), (11896, 0.055), (26420, 0.14), (70830, 0.30),
        (150000, 0.41), (double.infinity, 0.45)],
    2013: [(6011, 0.00), (11991, 0.055), (26631, 0.14), (71397, 0.30),
        (151200, 0.41), (double.infinity, 0.45)],
    // ---- Suppression tranche 5,5 % ----
    2014: [(9690, 0.00), (26764, 0.14), (71754, 0.30), (151956, 0.41),
        (double.infinity, 0.45)],
    2015: [(9700, 0.00), (26791, 0.14), (71826, 0.30), (152108, 0.41),
        (double.infinity, 0.45)],
    2016: [(9710, 0.00), (26818, 0.14), (71898, 0.30), (152260, 0.41),
        (double.infinity, 0.45)],
    2017: [(9807, 0.00), (27086, 0.14), (72617, 0.30), (153783, 0.41),
        (double.infinity, 0.45)],
    2018: [(9964, 0.00), (27519, 0.14), (73779, 0.30), (156244, 0.41),
        (double.infinity, 0.45)],
    2019: [(10064, 0.00), (27794, 0.14), (74517, 0.30), (157806, 0.41),
        (double.infinity, 0.45)],
    // ---- Taux 14 % abaissé à 11 % ----
    2020: [(10084, 0.00), (25710, 0.11), (73516, 0.30), (158122, 0.41),
        (double.infinity, 0.45)],
    2021: [(10225, 0.00), (26070, 0.11), (74545, 0.30), (160336, 0.41),
        (double.infinity, 0.45)],
    2022: [(10777, 0.00), (27478, 0.11), (78570, 0.30), (168994, 0.41),
        (double.infinity, 0.45)],
    2023: [(11294, 0.00), (28797, 0.11), (82341, 0.30), (177106, 0.41),
        (double.infinity, 0.45)],
    2024: [(11497, 0.00), (29315, 0.11), (83823, 0.30), (180294, 0.41),
        (double.infinity, 0.45)],
    2025: [(11600, 0.00), (29579, 0.11), (84577, 0.30), (181917, 0.41),
        (double.infinity, 0.45)],
  };

  /// Renvoie le barème IR pour l'année des revenus [year].
  /// Lève [BaremeIRIndisponible] si l'année n'est pas en table — jamais de
  /// fallback silencieux sur un autre millésime.
  static List<(double, double)> tranchesPour(int year) {
    final t = _baremes[year];
    if (t == null) throw BaremeIRIndisponible(year);
    return t;
  }

  /// `true` si on a un barème pour cette année.
  static bool aBaremePour(int year) => _baremes.containsKey(year);

  /// Liste triée des années disponibles.
  static List<int> get anneesDisponibles =>
      _baremes.keys.toList()..sort();

  /// Barème PS pour revenus fonciers (location nue) + plus-values immo
  /// particuliers. LFSS 2026 : maintien à 17,2 %.
  /// Clé = année des revenus.
  static const Map<int, PrelevementsSociaux> _psFoncier = {
    2018: PrelevementsSociaux(csg: 0.092, crds: 0.005, solidarite: 0.075),
    2019: PrelevementsSociaux(csg: 0.092, crds: 0.005, solidarite: 0.075),
    2020: PrelevementsSociaux(csg: 0.092, crds: 0.005, solidarite: 0.075),
    2021: PrelevementsSociaux(csg: 0.092, crds: 0.005, solidarite: 0.075),
    2022: PrelevementsSociaux(csg: 0.092, crds: 0.005, solidarite: 0.075),
    2023: PrelevementsSociaux(csg: 0.092, crds: 0.005, solidarite: 0.075),
    2024: PrelevementsSociaux(csg: 0.092, crds: 0.005, solidarite: 0.075),
    2025: PrelevementsSociaux(csg: 0.092, crds: 0.005, solidarite: 0.075),
    2026: PrelevementsSociaux(csg: 0.092, crds: 0.005, solidarite: 0.075),
  };

  /// Barème PS pour revenus meublés : LMNP, meublé de tourisme, bail mobilité.
  /// Taux identique aux revenus fonciers : 17,2 % (CSG 9,2 % + CRDS 0,5 % +
  /// prélèvement de solidarité 7,5 %) depuis 2018. Aucune divergence
  /// foncier/meublé n'a été instaurée à ce jour. Clé = année des revenus.
  static const Map<int, PrelevementsSociaux> _psMeuble = {
    2018: PrelevementsSociaux(csg: 0.092, crds: 0.005, solidarite: 0.075),
    2019: PrelevementsSociaux(csg: 0.092, crds: 0.005, solidarite: 0.075),
    2020: PrelevementsSociaux(csg: 0.092, crds: 0.005, solidarite: 0.075),
    2021: PrelevementsSociaux(csg: 0.092, crds: 0.005, solidarite: 0.075),
    2022: PrelevementsSociaux(csg: 0.092, crds: 0.005, solidarite: 0.075),
    2023: PrelevementsSociaux(csg: 0.092, crds: 0.005, solidarite: 0.075),
    2024: PrelevementsSociaux(csg: 0.092, crds: 0.005, solidarite: 0.075),
    2025: PrelevementsSociaux(csg: 0.092, crds: 0.005, solidarite: 0.075),
    2026: PrelevementsSociaux(csg: 0.092, crds: 0.005, solidarite: 0.075),
  };

  /// Détail PS sur revenus fonciers pour l'année [year].
  /// Lève [PrelevementsSociauxIndisponibles] si l'année n'est pas en table.
  static PrelevementsSociaux psFoncierPour(int year) {
    final p = _psFoncier[year];
    if (p == null) throw PrelevementsSociauxIndisponibles(year);
    return p;
  }

  /// Détail PS sur revenus meublés (LMNP, tourisme, bail mobilité) pour l'année [year].
  /// Lève [PrelevementsSociauxIndisponibles] si l'année n'est pas en table.
  static PrelevementsSociaux psMeublePour(int year) {
    final p = _psMeuble[year];
    if (p == null) throw PrelevementsSociauxIndisponibles(year);
    return p;
  }

  /// `true` si les deux barèmes PS (foncier + meublé) couvrent l'année.
  static bool aPSPour(int year) =>
      _psFoncier.containsKey(year) && _psMeuble.containsKey(year);

  /// Taux global PS foncier pour l'année [year].
  /// Avant 2018 : approximations historiques (15,5 % / 13,5 %).
  /// 2018+ : somme des composantes CSG + CRDS + solidarité.
  static double tauxPSFoncierPour(int year) {
    if (year < 2012) return 0.135;
    if (year < 2018) return 0.155;
    return psFoncierPour(year).total;
  }

  /// Taux global PS meublé pour l'année [year].
  /// LFSS 2026 : 18,6 % dès revenus 2025 (rétroactif).
  static double tauxPSMeublePour(int year) {
    if (year < 2012) return 0.135;
    if (year < 2018) return 0.155;
    return psMeublePour(year).total;
  }

  /// Alias rétro-compatible : tranches du dernier millésime disponible.
  static List<(double, double)> get tranches => tranchesPour(annee);

  /// Plafond de l'avantage du quotient familial : ~1 790 € par demi-part
  /// supplémentaire (LF 2026 art. 4).
  static const double plafondQuotientFamilialDemiPart = 1790;

  /// Décote pour foyers modestes (2026, valeurs indicatives à confirmer).
  static const double decoteCelibataire = 897;
  static const double decoteCouple = 1486;
  static const double tauxDecote = 0.4525;


  /// Plafond du déficit foncier imputable sur le revenu global.
  static const double plafondDeficitImputableGlobal = 10700;

  /// Plafond doublé pour travaux de rénovation énergétique (DPE E/F/G → A/B/C/D).
  /// Dispositif prorogé jusqu'au 31/12/2027.
  static const double plafondDeficitRenovationEnergetique = 21400;

  /// Plafond global des niches fiscales (par foyer, par an).
  static const double plafondGlobalNichesFiscales = 10000;

  /// Micro-foncier (location nue) : seuil de recettes brutes du foyer.
  /// Au-delà → régime réel obligatoire.
  static const double seuilMicroFoncier = 15000;

  /// Abattement forfaitaire micro-foncier (30 %).
  static const double abattementMicroFoncier = 0.30;

  /// Micro-BIC location meublée longue durée : seuil + abattement.
  static const double seuilMicroBIC = 77700;
  static const double abattementMicroBIC = 0.50;

  /// Micro-BIC meublé de tourisme CLASSÉ (Gîtes de France, chambres d'hôtes…).
  static const double seuilMicroBICTourismeClasse = 77700;
  static const double abattementMicroBICTourismeClasse = 0.71;

  /// Micro-BIC meublé de tourisme NON classé (Airbnb non classé).
  /// Durci par PLF 2026 : abattement 30 %, plafond 15 000 €.
  static const double seuilMicroBICTourismeNonClasse = 15000;
  static const double abattementMicroBICTourismeNonClasse = 0.30;

  /// Plancher d'imposition micro-BIC : si recettes après abattement < 305 € → 0.
  static const double plancherMicroBIC = 305;

  /// Seuil de LMP (cumulatif avec dépassement des autres revenus pro).
  static const double seuilRecettesLMP = 23000;

  /// Taux IS 2026 — PME éligibles (CA < 10 M€).
  static const double tauxISReduit = 0.15;
  static const double seuilISTauxReduit = 42500;
  static const double tauxISNormal = 0.25;

  /// Taux Loc'Avantages 2026 (sans intermédiation locative).
  /// IL = intermédiation locative (organisme agréé) → majoration.
  static const double tauxLocAvantagesIntermediaire = 0.15;   // Loc1
  static const double tauxLocAvantagesIntermediaireIL = 0.20; // Loc1 + IL
  static const double tauxLocAvantagesSocial = 0.35;          // Loc2
  static const double tauxLocAvantagesSocialIL = 0.40;        // Loc2 + IL
  static const double tauxLocAvantagesTresSocialIL = 0.65;    // Loc3 (IL obligatoire)

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

  /// Taux Loc'Avantages selon le niveau (Loc1/Loc2/Loc3) et la présence
  /// d'intermédiation locative (IL). Retourne 0 si pas un Loc'Avantages.
  static double tauxLocAvantages(DispositifFiscal d) {
    switch (d) {
      case DispositifFiscal.locAvantagesIntermediaire:
        return tauxLocAvantagesIntermediaire;
      case DispositifFiscal.locAvantagesIntermediaireIL:
        return tauxLocAvantagesIntermediaireIL;
      case DispositifFiscal.locAvantagesSocial:
        return tauxLocAvantagesSocial;
      case DispositifFiscal.locAvantagesSocialIL:
        return tauxLocAvantagesSocialIL;
      case DispositifFiscal.locAvantagesTresSocialIL:
        return tauxLocAvantagesTresSocialIL;
      default:
        return 0;
    }
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

  /// Calcule l'IR sur un revenu net imposable donné, à parts = 1, en
  /// utilisant le barème de l'année [year] (par défaut le millésime courant).
  static double impotPourUnePart(double revenuParPart, {int? year}) {
    if (revenuParPart <= 0) return 0;
    final tr = year == null ? tranches : tranchesPour(year);
    var impot = 0.0;
    var precedent = 0.0;
    for (final (limite, taux) in tr) {
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

  /// Prélèvements sociaux totaux (psFoncier + psMeuble). Taux dépendant de
  /// l'année et de la nature du revenu (LFSS 2026 : foncier 17,2 % maintenu ;
  /// meublé 18,6 % dès revenus 2025).
  final double prelevementsSociaux;

  /// PS sur revenu foncier imposable uniquement (17,2 % depuis 2018, maintenu).
  final double psFoncier;

  /// PS sur revenu LMNP/meublé imposable uniquement (18,6 % dès 2025).
  final double psMeuble;

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

  /// Recettes brutes totales LMP (location meublée professionnelle).
  final double recettesLmpBrutes;

  /// Bénéfice LMP imposable (positif) intégré au revenu global au barème.
  final double beneficeLmpImposable;

  /// Déficit LMP imputable sur le revenu global (sans plafond).
  final double deficitLmpImputableGlobal;

  /// Cotisations sociales indépendants (SSI) sur LMP (taux 30 % par défaut,
  /// à valider avec un comptable — planchers et assiette CSG non gérés).
  final double cotisationsSSI;

  /// `true` si le statut LMP est déclaré mais que les recettes ne dépassent
  /// pas 23 000 € (condition de l'art. 155 IV CGI non remplie).
  final bool lmpHorsConditions;

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
    this.psFoncier = 0,
    this.psMeuble = 0,
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
    this.recettesLmpBrutes = 0,
    this.beneficeLmpImposable = 0,
    this.deficitLmpImputableGlobal = 0,
    this.cotisationsSSI = 0,
    this.lmpHorsConditions = false,
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

  /// Total à payer du foyer = IR total net + prélèvements sociaux fonciers
  /// + cotisations SSI sur LMP.
  double get totalImpotFoyer =>
      impotRevenuFoyerNet + prelevementsSociaux + cotisationsSSI;
}

/// Service de calcul fiscal pour les revenus fonciers.
///
/// Phase 1 : location nue au régime réel + barème progressif IR + PS variables
/// selon année et nature (foncier 17,2 %, meublé 18,6 % dès 2025)
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
      case DispositifFiscal.locAvantagesIntermediaire:
      case DispositifFiscal.locAvantagesIntermediaireIL:
      case DispositifFiscal.locAvantagesSocial:
      case DispositifFiscal.locAvantagesSocialIL:
      case DispositifFiscal.locAvantagesTresSocialIL:
        // Dispositifs hors logique « réduction sur prix de revient » :
        //  - Borloo Ancien : abattement sur recettes (clos en 2022)
        //  - Loc'Avantages : réduction sur loyers bruts, traitée séparément
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
    // LMNP + Viager LMNP : régime BIC non pro (charges sociales = PS).
    final logementsLmnp = _logementService.all
        .where((l) =>
            l.statutFiscal == StatutFiscal.lmnp ||
            l.statutFiscal == StatutFiscal.viagerLmnp)
        .toList();
    // LMP : régime BIC pro (charges sociales = cotisations SSI).
    final logementsLmp = _logementService.all
        .where((l) => l.statutFiscal == StatutFiscal.lmp)
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
          // Plafond renforcé à 21 400 € si au moins un logement nu réel est
          // en rénovation énergétique cette année.
          final renoEnergetique = logementsNus
              .any((l) => l.enRenovationEnergetique);
          final plafond = renoEnergetique
              ? BaremeIR2026.plafondDeficitRenovationEnergetique
              : BaremeIR2026.plafondDeficitImputableGlobal;
          final imputable = math.min(partNonInterets, plafond);
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

    // ---- LMNP : calcul par logement selon le régime choisi ----
    // Chaque logement peut être en micro-BIC, réel BIC, tourisme classé
    // ou tourisme non classé (voir Logement.regimeLmnp).
    var recettesLmnp = 0.0;
    var revenuLmnpImposable = 0.0;
    for (final l in logementsLmnp) {
      final recettes = recettesBrutesLogement(l.id, year);
      recettesLmnp += recettes;
      revenuLmnpImposable += _calculerImposableLmnp(l, recettes, year);
    }
    final lmnpDepasseSeuil = recettesLmnp > BaremeIR2026.seuilMicroBIC;

    // ---- LMP : même calcul mais déficit imputable sur revenu global ----
    // Conditions LMP (art. 155 IV CGI) :
    //   - recettes meublées > 23 000 € ET
    //   - recettes meublées > autres revenus pro du foyer
    // Si le statut est LMP mais que la condition de seuil n'est pas remplie,
    // un avertissement est levé (lmpHorsConditions).
    var recettesLmp = 0.0;
    var resultatLmp = 0.0; // peut être négatif (déficit imputable revenu global)
    for (final l in logementsLmp) {
      final recettes = recettesBrutesLogement(l.id, year);
      recettesLmp += recettes;
      resultatLmp += _calculerResultatLmp(l, recettes, year);
    }
    final lmpHorsConditions =
        logementsLmp.isNotEmpty && recettesLmp <= BaremeIR2026.seuilRecettesLMP;

    // Si résultat LMP négatif → imputation sur revenu global (sans plafond).
    final deficitLmpImputableGlobal =
        resultatLmp < 0 ? -resultatLmp : 0.0;
    final beneficeLmpImposable = math.max(0.0, resultatLmp);

    // Cotisations SSI applicables au LMP (à la place des PS sur le LMP).
    // Taux indicatif 30 % — à valider avec un comptable. Pour l'instant
    // c'est une approximation qui ne couvre pas planchers / assiette CSG.
    const tauxSSILmp = 0.30;
    final cotisationsSSI = beneficeLmpImposable * tauxSSILmp;

    // ---- Prélèvements sociaux ----
    // Foncier (location nue) : 17,2 % maintenu (LFSS 2026).
    // Meublé (LMNP non pro) : 18,6 % dès revenus 2025 (LFSS 2026 rétroactif).
    final psFoncier =
        revenuFoncierImposable * BaremeIR2026.tauxPSFoncierPour(year);
    final psMeuble =
        revenuLmnpImposable * BaremeIR2026.tauxPSMeublePour(year);
    final ps = psFoncier + psMeuble;
    // Assiette IR : foncier + LMNP sont tous deux imposés au barème
    // progressif (le LMNP non pro entre dans le revenu global après
    // abattement micro-BIC ou réel selon le régime).
    final assietteImmobilier = revenuFoncierImposable + revenuLmnpImposable;

    // ---- IR avec barème progressif + abattement 10 % sur autres revenus ----
    // Les autres revenus du foyer (salaires, pensions…) peuvent être saisis
    // année par année (utile pour suivre une carrière qui évolue). À défaut,
    // on retombe sur la valeur par défaut du foyer.
    final autresRevenusNets = s.autresRevenusBrutsPour(year) * 0.9;
    // Les deux déficits s'imputent sur le revenu global :
    //  - déficit foncier (plafonné à 10 700 € ou 21 400 €)
    //  - déficit LMP (sans limite, art. 156-I 1° bis CGI)
    final deficitGlobalTotal =
        deficitImputableGlobal + deficitLmpImputableGlobal;
    // Le bénéfice LMP s'ajoute au revenu global (BIC pro, imposé au barème).
    final assietteSansFoncier =
        math.max(0.0, autresRevenusNets + beneficeLmpImposable - deficitGlobalTotal);
    final assietteAvecFoncier = math.max(
      0.0,
      autresRevenusNets + beneficeLmpImposable + assietteImmobilier - deficitGlobalTotal,
    );

    final irSans =
        _impotAvecQuotientFamilial(assietteSansFoncier, s.parts, year: year);
    final irAvec =
        _impotAvecQuotientFamilial(assietteAvecFoncier, s.parts, year: year);

    // TMI appliqué (estimé) — sur le barème de l'année.
    final parPart = s.parts > 0 ? assietteAvecFoncier / s.parts : 0.0;
    var tmi = 0.0;
    var prev = 0.0;
    for (final (limite, taux) in BaremeIR2026.tranchesPour(year)) {
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

    // ---- Loc'Avantages (réduction d'impôt sur loyers bruts) ----
    // Applicable au régime réel foncier, cumulable avec la déduction des
    // charges. La réduction s'impute sur l'IR (additionnel foncier).
    if (regimeNu == RegimeFiscal.reel) {
      for (final l in _logementService.all) {
        final taux = BaremeIR2026.tauxLocAvantages(l.dispositif);
        if (taux == 0) continue;
        if (!l.dispositifActifPour(year)) continue;
        final loyersBruts = recettesBrutesLogement(l.id, year);
        final reductionAnnuelle = loyersBruts * taux;
        reductions.add(ReductionDispositif(
          logement: l,
          dispositif: l.dispositif,
          anneeAcquisition: l.dateAcquisition?.year ?? year,
          dureeAnnees: 6,
          prixRevientPlafonne: loyersBruts,
          tauxTotal: taux,
          reductionAnnuelle: reductionAnnuelle,
          dansLaFenetre: true,
        ));
        reductionBrute += reductionAnnuelle;
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
      psFoncier: psFoncier,
      psMeuble: psMeuble,
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
      recettesLmpBrutes: recettesLmp,
      beneficeLmpImposable: beneficeLmpImposable,
      deficitLmpImputableGlobal: deficitLmpImputableGlobal,
      cotisationsSSI: cotisationsSSI,
      lmpHorsConditions: lmpHorsConditions,
    );
  }

  /// Imposable LMNP (non pro) pour un logement selon son régime.
  /// La règle de l'amortissement « ne crée pas de déficit » est appliquée :
  /// au réel BIC l'amortissement est limité au résultat avant amortissement.
  double _calculerImposableLmnp(Logement l, double recettes, int year) {
    switch (l.regimeLmnp) {
      case RegimeLmnp.microBIC:
        final imposable = recettes * (1 - BaremeIR2026.abattementMicroBIC);
        return imposable < BaremeIR2026.plancherMicroBIC ? 0 : imposable;
      case RegimeLmnp.tourismeClasse:
        final imposable =
            recettes * (1 - BaremeIR2026.abattementMicroBICTourismeClasse);
        return imposable < BaremeIR2026.plancherMicroBIC ? 0 : imposable;
      case RegimeLmnp.tourismeNonClasse:
        final imposable =
            recettes * (1 - BaremeIR2026.abattementMicroBICTourismeNonClasse);
        return imposable < BaremeIR2026.plancherMicroBIC ? 0 : imposable;
      case RegimeLmnp.reelBIC:
        final charges = chargesDeductiblesLogement(l.id, year);
        final interets = _creditService.interetsForLogementYear(l.id, year);
        final assurance = _creditService.assuranceForLogementYear(l.id, year);
        final amort = l.amortissementAnnuel;
        final avantAmort = recettes - charges - interets - assurance;
        // Amortissement plafonné au résultat positif (art. 39 C CGI).
        final amortDeductible = math.max(0.0, math.min(amort, avantAmort));
        // Le déficit hors amortissement est reportable 10 ans sur revenus
        // meublés (non implémenté ici — affichage à venir). On clamp à 0
        // pour ne pas l'imputer ailleurs.
        return math.max(0.0, avantAmort - amortDeductible);
    }
  }

  /// Résultat LMP (peut être négatif → déficit imputable revenu global).
  /// Même base que LMNP réel mais SANS plafond d'amortissement (art. 39 C
  /// continue de s'appliquer cependant pour cohérence).
  double _calculerResultatLmp(Logement l, double recettes, int year) {
    final charges = chargesDeductiblesLogement(l.id, year);
    final interets = _creditService.interetsForLogementYear(l.id, year);
    final assurance = _creditService.assuranceForLogementYear(l.id, year);
    final amort = l.amortissementAnnuel;
    final avantAmort = recettes - charges - interets - assurance;
    // Même règle qu'en LMNP : l'amortissement ne crée pas de déficit.
    final amortDeductible = math.max(0.0, math.min(amort, avantAmort));
    return avantAmort - amortDeductible;
  }

  /// IR avec quotient familial et plafonnement par demi-part.
  ///
  /// Méthode officielle : on calcule l'impôt avec le QF (assiette / parts)
  /// puis sans le QF (assiette / parts_ref où parts_ref = 1 pour célibataire,
  /// 2 pour couple). L'écart entre les deux est plafonné à
  /// 1 759 €/demi-part supplémentaire. L'impôt final est le **maximum** entre
  /// IR(quotient) et IR(parts_ref) − plafond.
  double _impotAvecQuotientFamilial(
    double assiette,
    double parts, {
    required int year,
  }) {
    if (assiette <= 0 || parts <= 0) return 0;
    final s = settings;
    final partsRef = s.marieOuPacse ? 2.0 : 1.0;
    final partsSupp = math.max(0.0, parts - partsRef);

    // Calcul avec quotient familial complet, sur le barème de l'année.
    final irAvecQf =
        BaremeIR2026.impotPourUnePart(assiette / parts, year: year) * parts;

    // Calcul de référence (sans demi-parts supplémentaires).
    final irRef =
        BaremeIR2026.impotPourUnePart(assiette / partsRef, year: year) *
            partsRef;

    // Avantage du QF plafonné : ~1 790 €/demi-part en 2025.
    final demiPartsSupp = partsSupp * 2;
    final plafondAvantage =
        demiPartsSupp * BaremeIR2026.plafondQuotientFamilialDemiPart;

    final avantageReel = irRef - irAvecQf;

    if (avantageReel <= plafondAvantage) {
      return irAvecQf;
    }
    return irRef - plafondAvantage;
  }
}
