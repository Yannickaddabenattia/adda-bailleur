import '../../models/contrat_bail.dart' show BailType;
import '../../models/fiscal_settings.dart';
import '../../models/logement.dart';

/// Configuration fiscale et juridique d'un **pays** (France, Belgique, Suisse).
///
/// Le pays est porté **par bien** (cf. ARCHITECTURE-MULTIPAYS) : chaque bien lit
/// la config de son pays pour la fiscalité, la garantie, l'indexation et les
/// modèles de documents.
///
/// Le **calcul fiscal par bien** ([computeRentalTax]) renvoie `null` pour la
/// France : sa fiscalité est calculée au niveau du **foyer** (barème progressif
/// global) par le moteur existant + l'écran dédié, qui ne sont pas modifiés.
/// La Belgique (RC forfaitaire) et la Suisse (taux marginal saisi) calculent
/// au niveau du **bien** et renvoient un [TaxEstimate].
abstract class CountryTaxConfig {
  /// Code pays : `'fr'` | `'be'` | `'ch'`.
  String get countryCode;

  /// Devise des montants du bien : `'EUR'` | `'CHF'`.
  String get currencyCode;

  /// Estimation de l'impôt locatif **pour un bien** et une année donnée.
  ///
  /// - France : renvoie `null` (fiscalité au niveau du foyer → écran existant).
  /// - Belgique / Suisse : renvoie un [TaxEstimate] (`isEstimate = true`).
  ///
  /// **Aucun calcul silencieux sur une valeur ⚠️ non vérifiée** : si une donnée
  /// requise manque (coefficient non publié, taux utilisateur non saisi…), elle
  /// est listée dans `TaxEstimate.missingInputs` et `estimatedTax` reste `null`
  /// pour que l'UI demande la saisie manuelle.
  TaxEstimate? computeRentalTax({
    required Logement logement,
    required int year,
    required FiscalSettings settings,
  });

  /// Règle de dépôt / garantie locative selon le bail et sa date de signature.
  DepositRule depositRule({
    required Logement logement,
    required DateTime leaseDate,
    BailType? bailType,
  });

  /// Mode d'indexation des loyers (IRL FR / indice santé BE / taux de
  /// référence + IPC CH).
  RentIndexationInfo indexationInfo({required Logement logement});

  /// Famille de modèle d'état des lieux propre au pays.
  String edlTemplateFamily({required Logement logement});

  /// Famille de modèles de bail propre au pays.
  String leaseTemplateFamily({required Logement logement});
}

/// Résultat d'une estimation fiscale par bien (Belgique / Suisse).
class TaxEstimate {
  final String currencyCode;

  /// Base imposable principale. `null` si une donnée requise manque.
  final double? taxableBase;

  /// Impôt estimé. `null` tant que [missingInputs] n'est pas vide — l'UI ne
  /// doit JAMAIS afficher un montant calculé sur une valeur manquante/⚠️.
  final double? estimatedTax;

  /// Toujours `true` pour BE/CH → l'UI affiche un bandeau « estimation ».
  final bool isEstimate;

  /// Détail du calcul (libellé + montant), pour l'écran fiscalité.
  final List<TaxLine> lines;

  /// Données manquantes à saisir (⚠️ non vérifiées ou champs vides du bien).
  final List<String> missingInputs;

  /// Renseigné si le calcul est volontairement indisponible
  /// (ex. plus-values, hors périmètre v1).
  final String? unavailableReason;

  const TaxEstimate({
    required this.currencyCode,
    this.taxableBase,
    this.estimatedTax,
    this.isEstimate = true,
    this.lines = const [],
    this.missingInputs = const [],
    this.unavailableReason,
  });

  /// `true` si toutes les données requises sont présentes (montant fiable).
  bool get isComplete => missingInputs.isEmpty && estimatedTax != null;
}

/// Une ligne de détail d'un [TaxEstimate].
class TaxLine {
  final String label;
  final double? amount;
  final String? note;
  const TaxLine(this.label, this.amount, {this.note});
}

/// Règle de dépôt / garantie locative.
/// [maxMonthsRent] `null` = à saisir manuellement / non plafonné.
class DepositRule {
  final int? maxMonthsRent;

  /// Compte bloqué au nom du locataire obligatoire (Belgique / Suisse).
  final bool blockedAccountRequired;

  final String note;

  const DepositRule({
    this.maxMonthsRent,
    this.blockedAccountRequired = false,
    this.note = '',
  });
}

/// Description du mode d'indexation des loyers d'un pays.
class RentIndexationInfo {
  /// Ex. `'IRL'`, `'Indice santé'`, `'Taux de référence + IPC'`.
  final String indexName;
  final String description;

  const RentIndexationInfo({
    required this.indexName,
    required this.description,
  });
}
