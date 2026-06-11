import '../../../models/contrat_bail.dart' show BailType;
import '../../../models/fiscal_settings.dart';
import '../../../models/logement.dart';
import '../country_tax_config.dart';

/// Implémentation **France** de [CountryTaxConfig].
///
/// Elle **délègue** au moteur fiscal français existant (`BaremeIR2026`,
/// `FiscaliteService`, `SCIService`) : **aucun calcul n'est modifié ni
/// déplacé**. Les tests `fiscal_ps_test`, etc. servent de filet de sécurité et
/// doivent rester verts à l'identique après cette extraction.
class FranceTaxConfig implements CountryTaxConfig {
  const FranceTaxConfig();

  @override
  String get countryCode => 'fr';

  @override
  String get currencyCode => 'EUR';

  /// La fiscalité française est calculée au niveau du **foyer** (barème
  /// progressif, quotient familial) par `FiscaliteService` + l'écran dédié.
  /// Il n'existe pas d'estimation « par bien » isolée : on renvoie `null`, et
  /// le routage UI (Phase E) dirige les biens français vers l'écran existant.
  @override
  TaxEstimate? computeRentalTax({
    required Logement logement,
    required int year,
    required FiscalSettings settings,
  }) =>
      null;

  @override
  DepositRule depositRule({
    required Logement logement,
    required DateTime leaseDate,
    BailType? bailType,
  }) {
    // Plafond légal français selon le type de bail (loi n°89-462) — délégué à
    // la logique existante `BailType.plafondDepotMois` (vide = 1, meublé = 2,
    // mobilité = 0, …). Pas de compte bloqué obligatoire en France.
    final months = (bailType ?? BailType.vide).plafondDepotMois;
    return DepositRule(maxMonthsRent: months, blockedAccountRequired: false);
  }

  @override
  RentIndexationInfo indexationInfo({required Logement logement}) =>
      const RentIndexationInfo(
        indexName: 'IRL',
        description:
            'Indice de référence des loyers (INSEE) — révision annuelle à la '
            'date convenue au bail.',
      );

  @override
  String edlTemplateFamily({required Logement logement}) => 'fr_alur';

  @override
  String leaseTemplateFamily({required Logement logement}) => 'fr';
}
