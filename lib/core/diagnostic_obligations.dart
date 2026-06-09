import '../models/diagnostic.dart';
import '../models/logement.dart';

/// Une obligation de diagnostic déduite des caractéristiques du logement.
class DiagnosticObligation {
  final DiagnosticType type;
  final String motif;
  const DiagnosticObligation(this.type, this.motif);
}

/// Détermine les diagnostics obligatoires pour un logement (location) selon la
/// réglementation, à partir de ses caractéristiques (année de construction,
/// permis, installations, assainissement, zone termites).
class DiagnosticObligations {
  static List<DiagnosticObligation> pour(Logement l) {
    final now = DateTime.now();
    final obligations = <DiagnosticObligation>[
      const DiagnosticObligation(
          DiagnosticType.dpe, 'Obligatoire pour toute location.'),
      const DiagnosticObligation(
          DiagnosticType.erp, 'Obligatoire pour toute location.'),
    ];

    int? age(DateTime? d) => d == null ? null : now.year - d.year;

    final ageElec = age(l.dateInstallationElectrique);
    if (ageElec != null && ageElec > 15) {
      obligations.add(const DiagnosticObligation(DiagnosticType.electrique,
          'Installation électrique de plus de 15 ans.'));
    }

    final ageGaz = age(l.dateInstallationGaz);
    if (ageGaz != null && ageGaz > 15) {
      obligations.add(const DiagnosticObligation(
          DiagnosticType.gaz, 'Installation de gaz de plus de 15 ans.'));
    }

    if (l.anneeConstruction != null && l.anneeConstruction! < 1949) {
      obligations.add(const DiagnosticObligation(
          DiagnosticType.plomb, 'Logement construit avant 1949.'));
    }

    final permis = l.datePermisConstruire;
    if (permis != null &&
        (permis.year < 1997 || (permis.year == 1997 && permis.month < 7))) {
      obligations.add(const DiagnosticObligation(DiagnosticType.amiante,
          'Permis de construire avant juillet 1997.'));
    }

    if (l.zoneTermites) {
      obligations.add(const DiagnosticObligation(
          DiagnosticType.termites, 'Logement en zone à risque termites.'));
    }

    if (l.typeAssainissement == TypeAssainissement.nonCollectif) {
      obligations.add(const DiagnosticObligation(
          DiagnosticType.assainissement, 'Assainissement non collectif.'));
    }

    return obligations;
  }

  /// Messages d'erreur pour les diagnostics obligatoires manquants ou expirés,
  /// en s'appuyant sur les diagnostics réellement enregistrés.
  static List<String> problemes(Logement l, List<Diagnostic> diagnostics) {
    final errors = <String>[];
    for (final o in pour(l)) {
      final matching = diagnostics.where((d) => d.type == o.type).toList();
      if (matching.isEmpty) {
        errors.add('Diagnostic ${o.type.label} manquant (${o.motif}).');
      } else if (matching.every((d) => d.estExpire)) {
        errors.add('Diagnostic ${o.type.label} expiré — à renouveler.');
      }
    }
    return errors;
  }
}
