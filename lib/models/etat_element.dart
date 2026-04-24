enum EtatElement {
  bon,
  moyen,
  mauvais,
  aRemplacer;

  String get label {
    switch (this) {
      case EtatElement.bon:
        return 'Bon état';
      case EtatElement.moyen:
        return 'Moyen';
      case EtatElement.mauvais:
        return 'Mauvais état';
      case EtatElement.aRemplacer:
        return 'À remplacer';
    }
  }

  static EtatElement fromString(String value) {
    return EtatElement.values.firstWhere(
      (e) => e.name == value,
      orElse: () => EtatElement.bon,
    );
  }
}
