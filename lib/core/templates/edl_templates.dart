import '../../models/element_piece.dart';
import '../../models/logement.dart';
import '../../models/piece.dart';

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

  static List<String> get suggestedPieceNames => [
        'Entrée',
        'Salon',
        'Séjour',
        'Salle à manger',
        'Cuisine',
        'Chambre',
        'Chambre parentale',
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

  static Piece _entree() => Piece.create(
        nom: 'Entrée',
        elements: [
          ..._common(),
          ElementPiece.create(nom: 'Porte d\'entrée'),
          ElementPiece.create(nom: 'Serrure'),
          ElementPiece.create(nom: 'Interphone / sonnette'),
        ],
      );

  static Piece _salon() => Piece.create(
        nom: 'Salon',
        elements: _common(),
      );

  static Piece _sam() => Piece.create(
        nom: 'Salle à manger',
        elements: _common(),
      );

  static Piece _cuisine() => Piece.create(
        nom: 'Cuisine',
        elements: [
          ..._common(),
          ElementPiece.create(nom: 'Évier'),
          ElementPiece.create(nom: 'Robinetterie'),
          ElementPiece.create(nom: 'Plan de travail'),
          ElementPiece.create(nom: 'Meubles hauts / bas'),
          ElementPiece.create(nom: 'Plaques de cuisson'),
          ElementPiece.create(nom: 'Four / micro-ondes'),
          ElementPiece.create(nom: 'Hotte aspirante'),
          ElementPiece.create(nom: 'Réfrigérateur'),
        ],
      );

  static Piece _chambre(String nom) => Piece.create(
        nom: nom,
        elements: [
          ..._common(),
          ElementPiece.create(nom: 'Placards'),
          ElementPiece.create(nom: 'Radiateur / chauffage'),
        ],
      );

  static Piece _salleDeBain() => Piece.create(
        nom: 'Salle de bain',
        elements: [
          ..._common(),
          ElementPiece.create(nom: 'Lavabo / vasque'),
          ElementPiece.create(nom: 'Robinetterie'),
          ElementPiece.create(nom: 'Baignoire / douche'),
          ElementPiece.create(nom: 'Carrelage'),
          ElementPiece.create(nom: 'Miroir'),
          ElementPiece.create(nom: 'Ventilation / VMC'),
        ],
      );

  static Piece _wc() => Piece.create(
        nom: 'WC',
        elements: [
          ..._common(),
          ElementPiece.create(nom: 'Cuvette'),
          ElementPiece.create(nom: 'Abattant'),
          ElementPiece.create(nom: 'Mécanisme de chasse'),
        ],
      );

  static Piece _buanderie() => Piece.create(
        nom: 'Buanderie',
        elements: [
          ..._common(),
          ElementPiece.create(nom: 'Branchements lave-linge'),
          ElementPiece.create(nom: 'Évacuation'),
        ],
      );

  static Piece _pieceDeVie(String nom) => Piece.create(
        nom: nom,
        elements: _common(),
      );

  static Piece _exterieur() => Piece.create(
        nom: 'Extérieur',
        elements: [
          ElementPiece.create(nom: 'Jardin / terrasse'),
          ElementPiece.create(nom: 'Clôture / portail'),
          ElementPiece.create(nom: 'Façade'),
          ElementPiece.create(nom: 'Toiture visible'),
        ],
      );
}
