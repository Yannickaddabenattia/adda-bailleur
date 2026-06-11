import 'package:hive_ce/hive.dart';

/// Paramètres fiscaux du foyer (globaux, pas par logement).
///
/// Stockage : un seul enregistrement, clé fixe `FiscalSettings.key`.
/// Le quotient familial s'applique au foyer entier, donc un seul réglage.
class FiscalSettings {
  static const String key = 'main';

  /// Nombre de parts fiscales (ex : célibataire 1, couple 2, +1 enfant 0,5…).
  double parts;

  /// Autres revenus annuels du foyer (salaires, pensions…), avant abattement 10 %.
  /// **Valeur par défaut** utilisée pour toute année non renseignée
  /// explicitement dans [autresRevenusBrutsParAnnee].
  double autresRevenusBruts;

  /// Autres revenus saisis année par année. Une entrée par année prime
  /// sur [autresRevenusBruts]. Utile pour suivre une carrière qui évolue.
  Map<int, double> autresRevenusBrutsParAnnee;

  /// Marié / pacsé (impose une seule déclaration commune).
  bool marieOuPacse;

  /// Déficits fonciers reportables, par année d'origine (clé = année).
  /// Imputables sur les revenus fonciers des 10 années suivantes.
  Map<int, double> deficitsReportables;

  /// Année du barème utilisé (informatif).
  int anneeBareme;

  /// Autres niches fiscales déjà déclarées hors revenus fonciers
  /// (services à la personne, dons, garde d'enfant…). Sert au plafonnement
  /// global des niches (10 000 €/an).
  double autresNichesFiscales;

  // ─── Multi-pays : taux utilisateur saisis (BE/CH) ─────────────────────────
  // En Belgique et en Suisse, il n'existe pas de taux national unique sur les
  // loyers : le calcul dépend du taux marginal personnel. Ces champs sont
  // nullable (défaut France = non utilisés) → données existantes intactes.

  /// **Belgique** — taux marginal IPP de l'utilisateur (25/40/45/50 %). `null`.
  double? tauxMarginalBE;

  /// **Belgique** — taux des centimes additionnels communaux (ex. 0,07). `null`.
  double? tauxCommunalBE;

  /// **Suisse** — taux marginal d'imposition global estimé (fédéral + cantonal
  /// + communal). `null` = à saisir.
  double? tauxMarginalCH;

  FiscalSettings({
    this.parts = 1.0,
    this.autresRevenusBruts = 0.0,
    this.marieOuPacse = false,
    Map<int, double>? deficitsReportables,
    this.anneeBareme = 2026,
    this.autresNichesFiscales = 0.0,
    Map<int, double>? autresRevenusBrutsParAnnee,
    this.tauxMarginalBE,
    this.tauxCommunalBE,
    this.tauxMarginalCH,
  })  : deficitsReportables = deficitsReportables ?? {},
        autresRevenusBrutsParAnnee = autresRevenusBrutsParAnnee ?? {};

  /// Revenus bruts (hors fonciers) à utiliser pour le calcul fiscal de [year].
  /// Retourne la valeur spécifique si renseignée, sinon la valeur par défaut.
  double autresRevenusBrutsPour(int year) =>
      autresRevenusBrutsParAnnee[year] ?? autresRevenusBruts;

  /// Solde de déficit reportable utilisable l'année [year]
  /// (déficits des 10 années précédentes, non encore consommés).
  double soldeReportableA(int year) {
    var total = 0.0;
    deficitsReportables.forEach((origin, montant) {
      if (origin < year && origin >= year - 10 && montant > 0) {
        total += montant;
      }
    });
    return total;
  }
}

class FiscalSettingsAdapter extends TypeAdapter<FiscalSettings> {
  @override
  final int typeId = 22;

  @override
  FiscalSettings read(BinaryReader reader) {
    final numFields = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < numFields; i++) reader.readByte(): reader.read(),
    };
    final rawDef = fields[3] as Map?;
    final deficits = <int, double>{};
    if (rawDef != null) {
      rawDef.forEach((k, v) {
        if (k is int && v is num) deficits[k] = v.toDouble();
      });
    }
    final rawRev = fields[6] as Map?;
    final revParAnnee = <int, double>{};
    if (rawRev != null) {
      rawRev.forEach((k, v) {
        if (k is int && v is num) revParAnnee[k] = v.toDouble();
      });
    }
    return FiscalSettings(
      parts: (fields[0] as num?)?.toDouble() ?? 1.0,
      autresRevenusBruts: (fields[1] as num?)?.toDouble() ?? 0.0,
      marieOuPacse: (fields[2] as bool?) ?? false,
      deficitsReportables: deficits,
      anneeBareme: (fields[4] as int?) ?? 2026,
      autresNichesFiscales: (fields[5] as num?)?.toDouble() ?? 0.0,
      autresRevenusBrutsParAnnee: revParAnnee,
      // Multi-pays (index 7+). Réglages français antérieurs : champs absents
      // → null, aucun impact sur le calcul France.
      tauxMarginalBE: (fields[7] as num?)?.toDouble(),
      tauxCommunalBE: (fields[8] as num?)?.toDouble(),
      tauxMarginalCH: (fields[9] as num?)?.toDouble(),
    );
  }

  @override
  void write(BinaryWriter writer, FiscalSettings obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.parts)
      ..writeByte(1)
      ..write(obj.autresRevenusBruts)
      ..writeByte(2)
      ..write(obj.marieOuPacse)
      ..writeByte(3)
      ..write(obj.deficitsReportables)
      ..writeByte(4)
      ..write(obj.anneeBareme)
      ..writeByte(5)
      ..write(obj.autresNichesFiscales)
      ..writeByte(6)
      ..write(obj.autresRevenusBrutsParAnnee)
      ..writeByte(7)
      ..write(obj.tauxMarginalBE)
      ..writeByte(8)
      ..write(obj.tauxCommunalBE)
      ..writeByte(9)
      ..write(obj.tauxMarginalCH);
  }
}
