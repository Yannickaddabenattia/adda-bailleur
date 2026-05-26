import 'package:hive_ce/hive.dart';
import 'package:uuid/uuid.dart';

/// Régime fiscal d'une SCI.
enum SCIRegime {
  /// SCI à l'IR (transparente fiscalement) : les associés déclarent leur
  /// quote-part de revenu foncier dans leur déclaration personnelle.
  /// Calculé comme location nue au régime réel.
  ir,

  /// SCI à l'IS : la société paie son propre impôt sur les sociétés.
  /// Les associés ne sont imposés qu'en cas de distribution (PFU 30 %).
  is_;

  String get label {
    switch (this) {
      case SCIRegime.ir:
        return 'IR (transparent)';
      case SCIRegime.is_:
        return 'IS';
    }
  }
}

/// Société Civile Immobilière nommée. Plusieurs logements peuvent y être
/// rattachés via le champ `Logement.sciId`.
class SCI {
  final String id;
  String nom;

  /// Régime fiscal "principal" de la SCI :
  /// - `ir` : SCI à l'IR par défaut. Si `anneeBasculeIS` est renseignée,
  ///   la SCI passe à l'IS à partir de cette année (option irrévocable au
  ///   sens du CGI).
  /// - `is_` : SCI à l'IS depuis sa création (pas de bascule possible).
  SCIRegime regime;

  /// Année à partir de laquelle la SCI bascule à l'IS (option exercée).
  /// `null` = pas de bascule prévue (la SCI reste sur son [regime] initial).
  /// Pertinent uniquement quand `regime == SCIRegime.ir`.
  int? anneeBasculeIS;

  final DateTime createdAt;
  DateTime updatedAt;

  /// Distributions de dividendes par année (clé = année, valeur = montant €).
  /// Soumis au PFU 30 % côté associés au niveau de la fiscalité personnelle.
  /// Uniquement pertinent pour les SCI à l'IS.
  Map<int, double> distributionsParAnnee;

  SCI({
    required this.id,
    required this.nom,
    required this.regime,
    required this.createdAt,
    required this.updatedAt,
    this.anneeBasculeIS,
    Map<int, double>? distributionsParAnnee,
  }) : distributionsParAnnee = distributionsParAnnee ?? {};

  factory SCI.create({
    required String nom,
    SCIRegime regime = SCIRegime.ir,
  }) {
    final now = DateTime.now().toUtc();
    return SCI(
      id: const Uuid().v4(),
      nom: nom.trim(),
      regime: regime,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Régime effectivement applicable pour [year] en tenant compte d'une
  /// éventuelle bascule IR→IS au cours de la vie de la SCI.
  SCIRegime regimeForYear(int year) {
    if (regime == SCIRegime.is_) return SCIRegime.is_;
    if (anneeBasculeIS != null && year >= anneeBasculeIS!) {
      return SCIRegime.is_;
    }
    return SCIRegime.ir;
  }

  double distributionPourAnnee(int year) => distributionsParAnnee[year] ?? 0;
}

class SCIAdapter extends TypeAdapter<SCI> {
  @override
  final int typeId = 17;

  @override
  SCI read(BinaryReader reader) {
    final numFields = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < numFields; i++) reader.readByte(): reader.read(),
    };
    final rawDistrib = fields[5] as Map?;
    final distrib = <int, double>{};
    if (rawDistrib != null) {
      rawDistrib.forEach((k, v) {
        if (k is int && v is num) distrib[k] = v.toDouble();
      });
    }
    return SCI(
      id: fields[0] as String,
      nom: fields[1] as String,
      regime: SCIRegime.values.firstWhere(
        (r) => r.name == (fields[2] as String),
        orElse: () => SCIRegime.ir,
      ),
      createdAt: DateTime.parse(fields[3] as String),
      updatedAt: DateTime.parse(fields[4] as String),
      distributionsParAnnee: distrib,
      anneeBasculeIS: fields[6] as int?,
    );
  }

  @override
  void write(BinaryWriter writer, SCI obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.nom)
      ..writeByte(2)
      ..write(obj.regime.name)
      ..writeByte(3)
      ..write(obj.createdAt.toIso8601String())
      ..writeByte(4)
      ..write(obj.updatedAt.toIso8601String())
      ..writeByte(5)
      ..write(obj.distributionsParAnnee)
      ..writeByte(6)
      ..write(obj.anneeBasculeIS);
  }
}
