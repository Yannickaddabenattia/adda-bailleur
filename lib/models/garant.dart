import 'package:uuid/uuid.dart';

/// Garant (caution) d'un bail. Embarqué directement dans [ContratBail]
/// (sérialisé sous forme de Map dans l'adapter Hive et le backup) : un garant
/// est propre à un contrat, pas besoin d'une box Hive dédiée.
class Garant {
  final String id;
  String nom;
  String prenom;
  String? adresse;
  String? telephone;
  String? email;

  /// Revenus mensuels nets déclarés (pour vérifier la solvabilité).
  double? revenusMensuels;

  /// Durée de l'engagement de caution en mois (null = durée du bail).
  int? dureeEngagementMois;

  /// Montant maximal garanti (null = non plafonné).
  double? montantMax;

  Garant({
    required this.id,
    required this.nom,
    required this.prenom,
    this.adresse,
    this.telephone,
    this.email,
    this.revenusMensuels,
    this.dureeEngagementMois,
    this.montantMax,
  });

  factory Garant.create({
    required String nom,
    required String prenom,
    String? adresse,
    String? telephone,
    String? email,
    double? revenusMensuels,
    int? dureeEngagementMois,
    double? montantMax,
  }) =>
      Garant(
        id: const Uuid().v4(),
        nom: nom.trim().toUpperCase(),
        prenom: prenom.trim(),
        adresse: adresse?.trim().isEmpty ?? true ? null : adresse!.trim(),
        telephone:
            telephone?.trim().isEmpty ?? true ? null : telephone!.trim(),
        email: email?.trim().isEmpty ?? true ? null : email!.trim().toLowerCase(),
        revenusMensuels: revenusMensuels,
        dureeEngagementMois: dureeEngagementMois,
        montantMax: montantMax,
      );

  String get fullName => '$prenom $nom';

  Map<String, dynamic> toMap() => {
        'id': id,
        'nom': nom,
        'prenom': prenom,
        if (adresse != null) 'adresse': adresse,
        if (telephone != null) 'telephone': telephone,
        if (email != null) 'email': email,
        if (revenusMensuels != null) 'revenusMensuels': revenusMensuels,
        if (dureeEngagementMois != null)
          'dureeEngagementMois': dureeEngagementMois,
        if (montantMax != null) 'montantMax': montantMax,
      };

  factory Garant.fromMap(Map<String, dynamic> m) => Garant(
        id: m['id'] as String? ?? const Uuid().v4(),
        nom: (m['nom'] as String?) ?? '',
        prenom: (m['prenom'] as String?) ?? '',
        adresse: m['adresse'] as String?,
        telephone: m['telephone'] as String?,
        email: m['email'] as String?,
        revenusMensuels: (m['revenusMensuels'] as num?)?.toDouble(),
        dureeEngagementMois: (m['dureeEngagementMois'] as num?)?.toInt(),
        montantMax: (m['montantMax'] as num?)?.toDouble(),
      );
}
