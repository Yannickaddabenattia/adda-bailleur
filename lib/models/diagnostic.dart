import 'package:hive_ce/hive.dart';
import 'package:uuid/uuid.dart';

/// Type de diagnostic immobilier obligatoire à annexer au bail.
enum DiagnosticType {
  dpe, // Diagnostic de Performance Énergétique
  erp, // État des Risques et Pollutions
  plomb, // Si construction avant 1949
  amiante, // Si permis avant juillet 1997
  termites,
  electrique, // Si installation > 15 ans
  gaz, // Si installation > 15 ans
  assainissement, // Si non collectif
  audit, // Audit énergétique
  autre;

  String get label {
    switch (this) {
      case DiagnosticType.dpe:
        return 'DPE';
      case DiagnosticType.erp:
        return 'ERP';
      case DiagnosticType.plomb:
        return 'Plomb';
      case DiagnosticType.amiante:
        return 'Amiante';
      case DiagnosticType.termites:
        return 'Termites';
      case DiagnosticType.electrique:
        return 'Électrique';
      case DiagnosticType.gaz:
        return 'Gaz';
      case DiagnosticType.assainissement:
        return 'Assainissement';
      case DiagnosticType.audit:
        return 'Audit énergétique';
      case DiagnosticType.autre:
        return 'Autre';
    }
  }

  String get description {
    switch (this) {
      case DiagnosticType.dpe:
        return 'Diagnostic de Performance Énergétique (classe A à G).';
      case DiagnosticType.erp:
        return 'État des Risques et Pollutions (obligatoire depuis juin 2023).';
      case DiagnosticType.plomb:
        return 'Constat de risque d\'exposition au plomb (constructions avant 1949).';
      case DiagnosticType.amiante:
        return 'Diagnostic amiante (permis de construire avant juillet 1997).';
      case DiagnosticType.termites:
        return 'État relatif à la présence de termites (zones infestées).';
      case DiagnosticType.electrique:
        return 'État de l\'installation intérieure d\'électricité (> 15 ans).';
      case DiagnosticType.gaz:
        return 'État de l\'installation intérieure de gaz (> 15 ans).';
      case DiagnosticType.assainissement:
        return 'Contrôle de l\'installation d\'assainissement non collectif.';
      case DiagnosticType.audit:
        return 'Audit énergétique (passoires thermiques F/G).';
      case DiagnosticType.autre:
        return 'Diagnostic complémentaire.';
    }
  }

  /// Durée de validité légale, en années. 0 = pas de péremption stricte.
  int get dureeValiditeAns {
    switch (this) {
      case DiagnosticType.dpe:
        return 10;
      case DiagnosticType.erp:
        return 0; // 6 mois en pratique mais hors validité stricte
      case DiagnosticType.plomb:
        return 0; // illimitée si négatif, 1 an si positif
      case DiagnosticType.amiante:
        return 0; // illimitée si négatif
      case DiagnosticType.termites:
        return 0; // 6 mois
      case DiagnosticType.electrique:
        return 6;
      case DiagnosticType.gaz:
        return 6;
      case DiagnosticType.assainissement:
        return 3;
      case DiagnosticType.audit:
        return 5;
      case DiagnosticType.autre:
        return 0;
    }
  }
}

/// Un diagnostic immobilier rattaché à un logement, avec sa date de
/// réalisation, son fichier PDF, et éventuellement des résultats clés
/// (classe DPE, etc.).
class Diagnostic {
  final String id;
  final String logementId;
  DiagnosticType type;
  DateTime dateRealisation;
  String? filePath;

  /// Résumé court (ex : « Classe D / Classe E », « Conforme », « Plomb absent »).
  String resume;

  /// Résultat structuré (cas DPE notamment) — JSON libre.
  /// Ex DPE : `{ 'classeEnergie': 'D', 'classeClimat': 'E', 'kwh': 165 }`.
  String? resultatsJson;

  final DateTime createdAt;
  DateTime updatedAt;

  Diagnostic({
    required this.id,
    required this.logementId,
    required this.type,
    required this.dateRealisation,
    this.filePath,
    this.resume = '',
    this.resultatsJson,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Diagnostic.create({
    required String logementId,
    required DiagnosticType type,
    required DateTime dateRealisation,
    String? filePath,
    String resume = '',
    String? resultatsJson,
  }) {
    final now = DateTime.now().toUtc();
    return Diagnostic(
      id: const Uuid().v4(),
      logementId: logementId,
      type: type,
      dateRealisation: dateRealisation,
      filePath: filePath,
      resume: resume,
      resultatsJson: resultatsJson,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// `true` si le diagnostic est expiré aujourd'hui (selon la durée légale
  /// de validité du type).
  bool get estExpire {
    final duree = type.dureeValiditeAns;
    if (duree == 0) return false;
    final expiration = DateTime(
      dateRealisation.year + duree,
      dateRealisation.month,
      dateRealisation.day,
    );
    return DateTime.now().isAfter(expiration);
  }

  DateTime? get dateExpiration {
    final duree = type.dureeValiditeAns;
    if (duree == 0) return null;
    return DateTime(
      dateRealisation.year + duree,
      dateRealisation.month,
      dateRealisation.day,
    );
  }
}

class DiagnosticAdapter extends TypeAdapter<Diagnostic> {
  @override
  final int typeId = 19;

  @override
  Diagnostic read(BinaryReader reader) {
    final n = reader.readByte();
    final f = <int, dynamic>{
      for (var i = 0; i < n; i++) reader.readByte(): reader.read(),
    };
    return Diagnostic(
      id: f[0] as String,
      logementId: f[1] as String,
      type: DiagnosticType.values.firstWhere(
        (t) => t.name == (f[2] as String?),
        orElse: () => DiagnosticType.autre,
      ),
      dateRealisation: DateTime.parse(f[3] as String),
      filePath: f[4] as String?,
      resume: (f[5] as String?) ?? '',
      resultatsJson: f[6] as String?,
      createdAt: DateTime.parse(f[7] as String),
      updatedAt: DateTime.parse(f[8] as String),
    );
  }

  @override
  void write(BinaryWriter writer, Diagnostic obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.logementId)
      ..writeByte(2)
      ..write(obj.type.name)
      ..writeByte(3)
      ..write(obj.dateRealisation.toIso8601String())
      ..writeByte(4)
      ..write(obj.filePath)
      ..writeByte(5)
      ..write(obj.resume)
      ..writeByte(6)
      ..write(obj.resultatsJson)
      ..writeByte(7)
      ..write(obj.createdAt.toIso8601String())
      ..writeByte(8)
      ..write(obj.updatedAt.toIso8601String());
  }
}
