import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Affiche une icône 3D multicolore depuis `assets/icons/`.
///
/// Les SVG conservent leurs couleurs d'origine (AUCUNE teinte/`colorFilter`
/// n'est appliquée) — équivalent du rendu `.original` de SwiftUI.
/// Remplace les anciens `Icon(Icons.x)` posés sur pastilles colorées.
///
/// Exemple : `AppIcon3D(name: 'icon-logements', size: 40)`
class AppIcon3D extends StatelessWidget {
  /// Nom de l'asset SANS chemin ni extension, ex. `icon-logements`.
  final String name;

  /// Côté du carré de rendu (pt). ~40 pour conserver l'alignement des lignes.
  final double size;

  const AppIcon3D({super.key, required this.name, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SvgPicture.asset(
        'assets/icons/$name.svg',
        width: size,
        height: size,
        fit: BoxFit.contain,
      ),
    );
  }
}
