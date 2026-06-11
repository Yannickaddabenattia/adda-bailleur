/// Modèles de documents légaux **par pays** (bail, état des lieux, quittance)
/// pour la Belgique et la Suisse.
///
/// Approche **data-first** : chaque document est une liste de sections/clauses
/// portant sa **référence légale** (`source`, à recopier en commentaire — leçon
/// LFSS 2026). Les données ⚠️ non vérifiées apparaissent comme **placeholders
/// visibles** `[À VALIDER JURISTE — <sujet>]`, jamais inventées. Une donnée
/// obligatoire manquante **bloque la génération** (cf. [CountryDocumentTemplate.guard]).
///
/// Tous les documents BE/CH portent le pied de page [kModeleIndicatifFooter].
library;

/// Marqueur de donnée à faire valider par un juriste local. Inséré tel quel
/// dans le texte des clauses et listé dans l'écran récapitulatif.
final RegExp placeholderRegExp = RegExp(r'\[À VALIDER JURISTE — [^\]]+\]');

/// Pied de page obligatoire de tous les documents BE/CH (A.2).
const String kModeleIndicatifFooter =
    'Modèle indicatif — faire valider par un professionnel local avant premier usage.';

/// Une section/clause d'un document, avec sa référence légale.
class LeaseSection {
  final String titre;
  final String contenu;

  /// 📚 Référence légale de la règle (à recopier en commentaire/tests).
  final String source;

  const LeaseSection({
    required this.titre,
    required this.contenu,
    required this.source,
  });

  /// Placeholders `[À VALIDER JURISTE — …]` présents dans cette section.
  List<String> get placeholders =>
      placeholderRegExp.allMatches(contenu).map((m) => m.group(0)!).toList();
}

/// Donnée obligatoire conditionnant la génération d'un document.
class RequiredField {
  /// Clé recherchée dans la map de données fournie au guard.
  final String key;

  /// Libellé affiché à l'utilisateur si la donnée manque.
  final String label;

  const RequiredField(this.key, this.label);
}

/// Résultat du contrôle de génération d'un document.
class DocumentGuardResult {
  final bool blocked;

  /// Libellés des champs obligatoires manquants (vide si non bloqué).
  final List<String> missing;

  const DocumentGuardResult({required this.blocked, required this.missing});
}

/// Modèle de document d'un pays (bail, EDL ou quittance).
class CountryDocumentTemplate {
  /// `'be'` | `'ch'`.
  final String countryCode;

  /// `'EUR'` | `'CHF'`.
  final String currencyCode;

  /// `'bail'` | `'edl'` | `'quittance'`.
  final String docType;

  final List<LeaseSection> sections;

  /// Données obligatoires : leur absence bloque la génération.
  final List<RequiredField> requiredFields;

  const CountryDocumentTemplate({
    required this.countryCode,
    required this.currencyCode,
    required this.docType,
    required this.sections,
    required this.requiredFields,
  });

  /// Pied de page obligatoire.
  String get footer => kModeleIndicatifFooter;

  /// Tous les placeholders du document (pour l'écran récapitulatif
  /// « [À VALIDER JURISTE] »).
  List<String> get placeholders =>
      sections.expand((s) => s.placeholders).toList();

  /// Contrôle de génération. **Bloque** si une donnée obligatoire est absente,
  /// nulle ou vide, et renvoie la liste des champs manquants (A.2 : génération
  /// bloquée avec liste des champs).
  DocumentGuardResult guard(Map<String, dynamic> data) {
    final missing = <String>[];
    for (final f in requiredFields) {
      final v = data[f.key];
      final absent = v == null ||
          (v is String && v.trim().isEmpty) ||
          (v is Iterable && v.isEmpty);
      if (absent) missing.add(f.label);
    }
    return DocumentGuardResult(blocked: missing.isNotEmpty, missing: missing);
  }
}
