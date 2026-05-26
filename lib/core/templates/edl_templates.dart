import '../../models/element_piece.dart';
import '../../models/logement.dart';
import '../../models/piece.dart';
import '../../models/plan_logement.dart';

/// Templates par défaut pour l'état des lieux, en fonction du type de logement.
///
/// Le propriétaire peut ensuite ajouter / modifier / supprimer librement des
/// pièces et des éléments avant finalisation.
class EdlTemplates {
  static List<Piece> defaultFor(LogementType type) {
    switch (type) {
      case LogementType.studio:
        return [
          _cuisine(),
          _salleDeBain(),
          _pieceDeVie('Pièce de vie'),
          _entree(),
        ];
      case LogementType.appartement:
        return [
          _entree(),
          _salon(),
          _cuisine(),
          _chambre('Chambre'),
          _salleDeBain(),
          _wc(),
        ];
      case LogementType.maison:
        return [
          _entree(),
          _salon(),
          _cuisine(),
          _sam(),
          _chambre('Chambre 1'),
          _chambre('Chambre 2'),
          _salleDeBain(),
          _wc(),
          _buanderie(),
          _exterieur(),
        ];
      case LogementType.autre:
        return [
          _pieceDeVie('Pièce principale'),
          _cuisine(),
          _salleDeBain(),
        ];
    }
  }

  /// Construit la liste des pièces d'un EDL à partir des **plans du
  /// logement** (`PlanLogement.rooms`). Pour chaque pièce nommée dans le
  /// plan, on déduit le type via [pieceFromName] qui retourne une `Piece`
  /// pré-remplie avec les bons accessoires (évier pour cuisine, lavabo pour
  /// SDB, etc.).
  ///
  /// Si aucun plan ne contient de pièce, retourne `null` — le caller
  /// retombera sur [defaultFor] basé sur le type de logement.
  static List<Piece>? fromPlans(List<PlanLogement> plans) {
    final rooms = plans.expand((p) => p.rooms).toList();
    if (rooms.isEmpty) return null;
    return rooms.map((r) => pieceFromName(r.name)).toList();
  }

  /// Retourne une `Piece` pré-remplie d'éléments en fonction du nom de
  /// la pièce (matching insensible à la casse et aux accents). Le nom
  /// reste tel que saisi par l'utilisateur — seul le template d'éléments
  /// est déduit. Si rien ne correspond, on retombe sur les éléments
  /// communs (sols, murs, plafond, peinture, éclairage…).
  static Piece pieceFromName(String name) {
    final key = _normalize(name);
    // Suite parentale : chambre + salle de bain (parfois dressing). Le test
    // doit être AVANT « chambre » et « salle de bain » pour ne pas être
    // intercepté par eux.
    if (key.contains('suite parentale') ||
        key.contains('suite parental') ||
        key == 'suite') {
      return Piece.create(nom: name, elements: _suiteParentaleElements());
    }
    if (key.contains('cuisine')) {
      return Piece.create(nom: name, elements: _cuisineElements());
    }
    if (key.contains('sdb') ||
        key.contains('salle de bain') ||
        key.contains('salle d eau') ||
        key.contains('douche')) {
      return Piece.create(nom: name, elements: _salleDeBainElements());
    }
    if (key.contains('wc') || key.contains('toilette')) {
      return Piece.create(nom: name, elements: _wcElements());
    }
    if (key.contains('chambre')) {
      return Piece.create(nom: name, elements: _chambreElements());
    }
    if (key.contains('entree') || key.contains('hall') || key.contains('couloir')) {
      return Piece.create(nom: name, elements: _entreeElements());
    }
    if (key.contains('buanderie') || key.contains('cellier')) {
      return Piece.create(nom: name, elements: _buanderieElements());
    }
    if (key.contains('exterieur') ||
        key.contains('jardin') ||
        key.contains('terrasse') ||
        key.contains('balcon') ||
        key.contains('cour')) {
      return Piece.create(nom: name, elements: _exterieurElements());
    }
    if (key.contains('garage') ||
        key.contains('cave') ||
        key.contains('parking') ||
        key.contains('box')) {
      return Piece.create(nom: name, elements: _annexeElements());
    }
    // Salon / séjour / salle à manger / bureau / dressing / pièce de vie
    // → éléments communs uniquement (rien de spécifique).
    return Piece.create(nom: name, elements: _common());
  }

  /// Normalise une chaîne pour matcher : lower-case + suppression des
  /// accents les plus courants en français.
  static String _normalize(String s) {
    const map = {
      'à': 'a', 'â': 'a', 'ä': 'a',
      'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
      'î': 'i', 'ï': 'i',
      'ô': 'o', 'ö': 'o',
      'ù': 'u', 'û': 'u', 'ü': 'u',
      'ç': 'c',
    };
    final buffer = StringBuffer();
    for (final rune in s.toLowerCase().runes) {
      final ch = String.fromCharCode(rune);
      buffer.write(map[ch] ?? ch);
    }
    return buffer.toString();
  }

  static List<String> get suggestedPieceNames => [
        'Entrée',
        'Salon',
        'Séjour',
        'Salle à manger',
        'Cuisine',
        'Chambre',
        'Chambre parentale',
        'Suite parentale',
        'Chambre enfant',
        'Salle de bain',
        'Douche',
        'WC',
        'Bureau',
        'Dressing',
        'Buanderie',
        'Cave',
        'Garage',
        'Balcon',
        'Terrasse',
        'Jardin',
        'Extérieur',
      ];

  // --- Helpers ---------------------------------------------------------------

  static List<ElementPiece> _common() => [
        ElementPiece.create(nom: 'Sols'),
        ElementPiece.create(nom: 'Murs'),
        ElementPiece.create(nom: 'Plafond'),
        ElementPiece.create(nom: 'Peinture'),
        ElementPiece.create(nom: 'Éclairage'),
        ElementPiece.create(nom: 'Prises électriques'),
        ElementPiece.create(nom: 'Fenêtres / volets'),
      ];

  static Piece _entree() =>
      Piece.create(nom: 'Entrée', elements: _entreeElements());

  static Piece _salon() => Piece.create(nom: 'Salon', elements: _common());

  static Piece _sam() =>
      Piece.create(nom: 'Salle à manger', elements: _common());

  static Piece _cuisine() =>
      Piece.create(nom: 'Cuisine', elements: _cuisineElements());

  static Piece _chambre(String nom) =>
      Piece.create(nom: nom, elements: _chambreElements());

  static Piece _salleDeBain() =>
      Piece.create(nom: 'Salle de bain', elements: _salleDeBainElements());

  static Piece _wc() => Piece.create(nom: 'WC', elements: _wcElements());

  static Piece _buanderie() =>
      Piece.create(nom: 'Buanderie', elements: _buanderieElements());

  static Piece _pieceDeVie(String nom) =>
      Piece.create(nom: nom, elements: _common());

  static Piece _exterieur() =>
      Piece.create(nom: 'Extérieur', elements: _exterieurElements());

  // --- Listes d'éléments réutilisables (via pieceFromName) -------------------

  static List<ElementPiece> _entreeElements() => [
        ..._common(),
        ElementPiece.create(nom: 'Porte d\'entrée'),
        ElementPiece.create(nom: 'Serrure'),
        ElementPiece.create(nom: 'Interphone / sonnette'),
      ];

  static List<ElementPiece> _cuisineElements() => [
        ..._common(),
        ElementPiece.create(nom: 'Évier'),
        ElementPiece.create(nom: 'Robinetterie'),
        ElementPiece.create(nom: 'Plan de travail'),
        ElementPiece.create(nom: 'Meubles hauts / bas'),
        ElementPiece.create(nom: 'Plaques de cuisson'),
        ElementPiece.create(nom: 'Four / micro-ondes'),
        ElementPiece.create(nom: 'Hotte aspirante'),
        ElementPiece.create(nom: 'Réfrigérateur'),
      ];

  static List<ElementPiece> _chambreElements() => [
        ..._common(),
        ElementPiece.create(nom: 'Placards'),
        ElementPiece.create(nom: 'Radiateur / chauffage'),
      ];

  /// Suite parentale = chambre + salle de bain attenante (+ souvent dressing).
  /// On combine les éléments des deux et on ajoute un dressing.
  static List<ElementPiece> _suiteParentaleElements() => [
        ..._common(),
        // Partie chambre
        ElementPiece.create(nom: 'Placards / dressing'),
        ElementPiece.create(nom: 'Radiateur / chauffage'),
        // Partie salle de bain attenante
        ElementPiece.create(nom: 'Lavabo / vasque'),
        ElementPiece.create(nom: 'Robinetterie'),
        ElementPiece.create(nom: 'Baignoire / douche'),
        ElementPiece.create(nom: 'Carrelage'),
        ElementPiece.create(nom: 'Miroir'),
        ElementPiece.create(nom: 'Ventilation / VMC'),
      ];

  static List<ElementPiece> _salleDeBainElements() => [
        ..._common(),
        ElementPiece.create(nom: 'Lavabo / vasque'),
        ElementPiece.create(nom: 'Robinetterie'),
        ElementPiece.create(nom: 'Baignoire / douche'),
        ElementPiece.create(nom: 'Carrelage'),
        ElementPiece.create(nom: 'Miroir'),
        ElementPiece.create(nom: 'Ventilation / VMC'),
      ];

  static List<ElementPiece> _wcElements() => [
        ..._common(),
        ElementPiece.create(nom: 'Cuvette'),
        ElementPiece.create(nom: 'Abattant'),
        ElementPiece.create(nom: 'Mécanisme de chasse'),
      ];

  static List<ElementPiece> _buanderieElements() => [
        ..._common(),
        ElementPiece.create(nom: 'Branchements lave-linge'),
        ElementPiece.create(nom: 'Évacuation'),
      ];

  static List<ElementPiece> _exterieurElements() => [
        ElementPiece.create(nom: 'Jardin / terrasse'),
        ElementPiece.create(nom: 'Clôture / portail'),
        ElementPiece.create(nom: 'Façade'),
        ElementPiece.create(nom: 'Toiture visible'),
      ];

  static List<ElementPiece> _annexeElements() => [
        ElementPiece.create(nom: 'Sols'),
        ElementPiece.create(nom: 'Murs'),
        ElementPiece.create(nom: 'Plafond'),
        ElementPiece.create(nom: 'Éclairage'),
        ElementPiece.create(nom: 'Porte'),
      ];
}
