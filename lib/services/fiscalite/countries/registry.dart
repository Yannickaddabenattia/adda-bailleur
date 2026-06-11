import '../../../models/country.dart';
import '../country_tax_config.dart';
import 'belgium.dart';
import 'france.dart';
import 'switzerland.dart';

/// Retourne la [CountryTaxConfig] correspondant au pays d'un bien.
///
/// Point d'entrée unique du multi-pays : tous les écrans/services passent par
/// ici plutôt que d'instancier une config en dur. Belgique et Suisse sont
/// branchées aux Phases C et D ; tant que `AppConstants.multiPaysActif` est
/// `false`, seul [Country.france] est atteignable (aucun bien BE/CH créable).
CountryTaxConfig countryConfigFor(Country country) {
  switch (country) {
    case Country.france:
      return const FranceTaxConfig();
    case Country.belgique:
      return const BelgiumTaxConfig();
    case Country.suisse:
      return const SwitzerlandTaxConfig();
  }
}
