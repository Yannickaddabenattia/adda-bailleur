/// Pays de localisation d'un bien (multi-pays — cf. ARCHITECTURE-MULTIPAYS).
///
/// Le pays est porté **par bien**, jamais globalement. Stocké en base par son
/// `.name` (String) → ajouter une valeur ou réordonner ne casse pas les
/// données existantes. Défaut : [Country.france].
enum Country {
  france,
  belgique,
  suisse;

  /// Code court aligné sur `CountryTaxConfig.countryCode` : `fr` | `be` | `ch`.
  String get code => switch (this) {
        Country.france => 'fr',
        Country.belgique => 'be',
        Country.suisse => 'ch',
      };

  String get label => switch (this) {
        Country.france => 'France',
        Country.belgique => 'Belgique',
        Country.suisse => 'Suisse',
      };

  String get flag => switch (this) {
        Country.france => '🇫🇷',
        Country.belgique => '🇧🇪',
        Country.suisse => '🇨🇭',
      };

  /// Devise par défaut du pays (modifiable par bien). CHF pour la Suisse,
  /// EUR sinon.
  String get defaultCurrency => this == Country.suisse ? 'CHF' : 'EUR';

  static Country fromName(String? value) => Country.values.firstWhere(
        (c) => c.name == value,
        orElse: () => Country.france,
      );
}

/// Région belge (porte le droit du bail régionalisé + le précompte immobilier).
/// Nullable sur le bien : ne concerne que [Country.belgique].
enum BeRegion {
  wallonie,
  bruxelles,
  flandre;

  String get label => switch (this) {
        BeRegion.wallonie => 'Wallonie',
        BeRegion.bruxelles => 'Bruxelles-Capitale',
        BeRegion.flandre => 'Flandre',
      };

  static BeRegion? fromName(String? value) {
    if (value == null) return null;
    for (final r in BeRegion.values) {
      if (r.name == value) return r;
    }
    return null;
  }
}

/// Canton suisse (26). Nullable sur le bien : ne concerne que [Country.suisse].
/// Sert au taux d'impôt foncier ‰, aux barèmes de gains immobiliers et aux
/// overrides cantonaux du forfait d'entretien.
enum ChCanton {
  zh,
  be,
  lu,
  ur,
  sz,
  ow,
  nw,
  gl,
  zg,
  fr,
  so,
  bs,
  bl,
  sh,
  ar,
  ai,
  sg,
  gr,
  ag,
  tg,
  ti,
  vd,
  vs,
  ne,
  ge,
  ju;

  /// Abréviation officielle en majuscules (ex. `GE`, `VD`).
  String get code => name.toUpperCase();

  String get nom => switch (this) {
        ChCanton.zh => 'Zurich',
        ChCanton.be => 'Berne',
        ChCanton.lu => 'Lucerne',
        ChCanton.ur => 'Uri',
        ChCanton.sz => 'Schwyz',
        ChCanton.ow => 'Obwald',
        ChCanton.nw => 'Nidwald',
        ChCanton.gl => 'Glaris',
        ChCanton.zg => 'Zoug',
        ChCanton.fr => 'Fribourg',
        ChCanton.so => 'Soleure',
        ChCanton.bs => 'Bâle-Ville',
        ChCanton.bl => 'Bâle-Campagne',
        ChCanton.sh => 'Schaffhouse',
        ChCanton.ar => 'Appenzell Rh.-Ext.',
        ChCanton.ai => 'Appenzell Rh.-Int.',
        ChCanton.sg => 'Saint-Gall',
        ChCanton.gr => 'Grisons',
        ChCanton.ag => 'Argovie',
        ChCanton.tg => 'Thurgovie',
        ChCanton.ti => 'Tessin',
        ChCanton.vd => 'Vaud',
        ChCanton.vs => 'Valais',
        ChCanton.ne => 'Neuchâtel',
        ChCanton.ge => 'Genève',
        ChCanton.ju => 'Jura',
      };

  String get label => '$code — $nom';

  static ChCanton? fromName(String? value) {
    if (value == null) return null;
    for (final c in ChCanton.values) {
      if (c.name == value) return c;
    }
    return null;
  }
}
