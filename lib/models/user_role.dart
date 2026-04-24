enum UserRole {
  proprietaire,
  locataire;

  String get label {
    switch (this) {
      case UserRole.proprietaire:
        return 'Propriétaire';
      case UserRole.locataire:
        return 'Locataire';
    }
  }

  String get description {
    switch (this) {
      case UserRole.proprietaire:
        return 'Je gère un ou plusieurs logements et leurs locataires.';
      case UserRole.locataire:
        return 'Je consulte mes états des lieux et mes quittances.';
    }
  }

  static UserRole fromString(String value) {
    return UserRole.values.firstWhere(
      (r) => r.name == value,
      orElse: () => throw ArgumentError('Rôle inconnu : $value'),
    );
  }
}
