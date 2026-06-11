import '../../models/contrat_bail.dart' show BailType;
import '../../models/country.dart';

/// Mode d'adaptation/indexation du loyer (par pays).
enum IndexationMode {
  irl, // France
  indiceSante, // Belgique
  tauxReference, // Suisse — taux hypothécaire de référence (OFL)
  indexeIPC, // Suisse — bail indexé sur l'IPC (≥ 5 ans)
  echelonne; // Suisse — bail échelonné (≥ 3 ans)

  String get label => switch (this) {
        IndexationMode.irl => 'IRL (indice de référence des loyers)',
        IndexationMode.indiceSante => 'Indice santé',
        IndexationMode.tauxReference => 'Taux de référence (OFL)',
        IndexationMode.indexeIPC => 'Bail indexé (IPC)',
        IndexationMode.echelonne => 'Bail échelonné',
      };
}

/// Validations des règles locales (dépôt de garantie, indexation) **par pays**.
///
/// Chaque message d'erreur **cite sa source légale** (D : « Garantie limitée à
/// 3 mois — art. 257e CO »). Aucune valeur inventée : les plafonds proviennent
/// des textes référencés en B, C et dans `CountryTaxConfig`.
class CountryValidations {
  const CountryValidations._();

  // ─────────────────────────── DÉPÔT DE GARANTIE ───────────────────────────

  /// Plafond légal du dépôt, en mois de loyer, ou `null` si non déterminé.
  static int? depositCapMonths({
    required Country country,
    BeRegion? region,
    BailType? bailType,
    DateTime? leaseDate,
  }) {
    switch (country) {
      case Country.france:
        // 1 nu / 2 meublé / 0 mobilité.
        return (bailType ?? BailType.vide).plafondDepotMois;
      case Country.belgique:
        if (region == BeRegion.flandre) {
          final apres2019 =
              leaseDate != null && !leaseDate.isBefore(DateTime(2019, 1, 1));
          return apres2019 ? 3 : 2;
        }
        if (region == BeRegion.bruxelles) {
          // Ord. 04/04/2024 : baux ≥ 01/11/2024 → max 2 mois (toutes formes) ;
          // avant : 2 mois compte / 3 mois bancaire (plafond légal = 3).
          final apresReforme =
              leaseDate != null && !leaseDate.isBefore(DateTime(2024, 11, 1));
          return apresReforme ? 2 : 3;
        }
        return 2; // Wallonie (art. 20, compte) / fédéral antérieur
      case Country.suisse:
        return 3;
    }
  }

  /// Erreur sourcée si [moisDepot] dépasse le plafond légal, sinon `null`.
  static String? depositError({
    required Country country,
    BeRegion? region,
    BailType? bailType,
    DateTime? leaseDate,
    required double moisDepot,
  }) {
    final cap = depositCapMonths(
      country: country,
      region: region,
      bailType: bailType,
      leaseDate: leaseDate,
    );
    if (cap == null) return null;
    if (moisDepot > cap + 1e-9) {
      return 'Dépôt limité à $cap mois — ${_depositSource(country, region)}.';
    }
    return null;
  }

  static String _depositSource(Country country, BeRegion? region) {
    switch (country) {
      case Country.france:
        return 'loi n°89-462 (art. 22), loi ELAN';
      case Country.belgique:
        switch (region) {
          case BeRegion.wallonie:
            return 'décret wallon du 15/03/2018 art. 20';
          case BeRegion.bruxelles:
            return 'Code bruxellois du Logement art. 248 (ord. 04/04/2024)';
          case BeRegion.flandre:
            return 'Vlaams Woninghuurdecreet art. 37 (baux ≥ 01/01/2019)';
          case null:
            return 'art. 10 loi du 20/02/1991';
        }
      case Country.suisse:
        return 'art. 257e CO';
    }
  }

  // ─────────────────────────────── INDEXATION ──────────────────────────────

  /// Modes d'indexation autorisés dans le pays.
  static Set<IndexationMode> allowedIndexationModes(Country country) =>
      switch (country) {
        Country.france => {IndexationMode.irl},
        Country.belgique => {IndexationMode.indiceSante},
        Country.suisse => {
            IndexationMode.tauxReference,
            IndexationMode.indexeIPC,
            IndexationMode.echelonne,
          },
      };

  /// Erreur sourcée si [mode] n'est pas applicable dans le pays, sinon `null`.
  /// (D : « IRL réservé à la France ».)
  static String? indexationModeError({
    required Country country,
    required IndexationMode mode,
  }) {
    if (allowedIndexationModes(country).contains(mode)) return null;
    return '${mode.label} n\'est pas applicable en ${country.label} — '
        '${_indexationSource(country)}.';
  }

  static String _indexationSource(Country country) => switch (country) {
        Country.france => 'IRL : art. 17-1 loi 89-462',
        Country.belgique => 'indice santé : art. 1728bis ancien Code civil',
        Country.suisse => 'CO art. 269b/269c/269d, OBLF',
      };

  /// **Belgique** — l'indexation requiert les deux indices santé (base +
  /// nouveau). 📚 art. 1728bis ancien Code civil.
  static String? belgiumIndexationError({
    double? indiceSanteBase,
    double? indiceSanteNouveau,
  }) {
    if (indiceSanteBase == null || indiceSanteNouveau == null) {
      return 'Indexation : indices santé (base + nouveau) requis — '
          'art. 1728bis ancien Code civil.';
    }
    return null;
  }

  /// **Suisse** — bail indexé sur l'IPC : durée minimale de 5 ans.
  /// 📚 art. 269b CO.
  static String? swissIndexedLeaseError({required int dureeAnnees}) {
    if (dureeAnnees < 5) {
      return 'Bail indexé : durée minimale de 5 ans — art. 269b CO.';
    }
    return null;
  }

  /// **Suisse** — bail échelonné : durée minimale de 3 ans. 📚 art. 269c CO.
  static String? swissStaggeredLeaseError({required int dureeAnnees}) {
    if (dureeAnnees < 3) {
      return 'Bail échelonné : durée minimale de 3 ans — art. 269c CO.';
    }
    return null;
  }
}
