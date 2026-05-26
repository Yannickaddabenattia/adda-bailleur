import 'package:flutter/foundation.dart';

import '../core/storage/local_database.dart';
import '../models/contrat_bail.dart';

/// Catégorie d'un rappel pour permettre un filtrage / un libellé adapté.
enum RappelKind {
  preavisBailleur,
  preavisLocataire,
  finBail,
  regularisationCharges,
  diagnosticExpire,
  diagnosticProche,
}

/// Un rappel utilisateur ponctuel généré à la volée à partir des données
/// stockées (bails, diagnostics, dates de régularisation…).
class Rappel {
  final String id;
  final RappelKind kind;
  final DateTime date;
  final String titre;
  final String description;

  /// Lien d'origine (id du bail, du diagnostic, etc.) pour permettre la
  /// navigation directe depuis l'écran de rappels.
  final String? sourceId;

  /// Sévérité : 0 = info, 1 = bientôt, 2 = urgent / expiré.
  final int severite;

  const Rappel({
    required this.id,
    required this.kind,
    required this.date,
    required this.titre,
    required this.description,
    this.sourceId,
    this.severite = 0,
  });

  /// `true` si la date du rappel est passée.
  bool get estPasse => DateTime.now().isAfter(date);
}

/// Calcule l'ensemble des rappels actifs : préavis (6 mois bailleur, 3 mois
/// locataire), régularisation annuelle des charges, expirations de
/// diagnostics. Stateless — relit la base à chaque appel.
class RappelService extends ChangeNotifier {
  /// Tous les rappels, triés par date croissante (les plus proches d'abord),
  /// limités aux rappels actifs (passés ≤ 90 jours et futurs ≤ 365 jours).
  List<Rappel> compute() {
    final now = DateTime.now();
    final fenetreFuturFin = now.add(const Duration(days: 365));
    final fenetrePasseDebut = now.subtract(const Duration(days: 90));
    final result = <Rappel>[];

    // ---- Bails : préavis + fin + régularisation ----
    for (final c in LocalDatabase.contratsBailBox.values) {
      if (c.statut == BailStatus.brouillon ||
          c.statut == BailStatus.resilie ||
          c.statut == BailStatus.termine) {
        continue;
      }

      // Préavis bailleur : N mois avant la fin du bail.
      if (c.preavisBailleurMois > 0) {
        final dPrev =
            _subtractMonths(c.dateFin, c.preavisBailleurMois);
        if (_inWindow(dPrev, fenetrePasseDebut, fenetreFuturFin)) {
          result.add(Rappel(
            id: 'preavis-bail-${c.id}',
            kind: RappelKind.preavisBailleur,
            date: dPrev,
            titre: 'Préavis bailleur — ${c.reference}',
            description:
                'Date limite pour donner congé au locataire (${c.preavisBailleurMois} mois '
                'avant la fin du bail prévue le ${_d(c.dateFin)}).',
            sourceId: c.id,
            severite: dPrev.isBefore(now) ? 2 : 1,
          ));
        }
      }

      // Préavis locataire : N mois avant la fin.
      if (c.preavisLocataireMois > 0) {
        final dPrev =
            _subtractMonths(c.dateFin, c.preavisLocataireMois);
        if (_inWindow(dPrev, fenetrePasseDebut, fenetreFuturFin)) {
          result.add(Rappel(
            id: 'preavis-loc-${c.id}',
            kind: RappelKind.preavisLocataire,
            date: dPrev,
            titre: 'Préavis locataire — ${c.reference}',
            description:
                'Si le locataire veut partir, son préavis (${c.preavisLocataireMois} mois) '
                'doit être posé d\'ici cette date.',
            sourceId: c.id,
            severite: 0,
          ));
        }
      }

      // Fin de bail.
      if (_inWindow(c.dateFin, fenetrePasseDebut, fenetreFuturFin)) {
        result.add(Rappel(
          id: 'fin-${c.id}',
          kind: RappelKind.finBail,
          date: c.dateFin,
          titre: 'Fin du bail — ${c.reference}',
          description:
              'Le bail ${c.type.label.toLowerCase()} se termine. Organise l\'état des lieux de sortie.',
          sourceId: c.id,
          severite: 1,
        ));
      }

      // Régularisation annuelle : à la date anniversaire de prise d'effet.
      if (c.regularisationChargesAnnuelle) {
        final annivCetteAnnee =
            DateTime(now.year, c.dateDebut.month, c.dateDebut.day);
        var anniv = annivCetteAnnee;
        if (anniv.isBefore(now.subtract(const Duration(days: 30)))) {
          anniv = DateTime(now.year + 1, c.dateDebut.month, c.dateDebut.day);
        }
        if (_inWindow(anniv, fenetrePasseDebut, fenetreFuturFin)) {
          result.add(Rappel(
            id: 'regul-${c.id}-${anniv.year}',
            kind: RappelKind.regularisationCharges,
            date: anniv,
            titre: 'Régularisation des charges — ${c.reference}',
            description:
                'Date anniversaire du bail : calcule l\'écart entre provisions '
                'et charges réelles, ajuste la quittance.',
            sourceId: c.id,
            severite: 0,
          ));
        }
      }
    }

    // ---- Diagnostics : expiration ----
    for (final d in LocalDatabase.diagnosticsBox.values) {
      final exp = d.dateExpiration;
      if (exp == null) continue;
      if (!_inWindow(exp, fenetrePasseDebut, fenetreFuturFin)) continue;
      final isExpired = exp.isBefore(now);
      result.add(Rappel(
        id: 'diag-${d.id}',
        kind: isExpired
            ? RappelKind.diagnosticExpire
            : RappelKind.diagnosticProche,
        date: exp,
        titre:
            '${isExpired ? "Diagnostic expiré" : "Diagnostic à renouveler"} — ${d.type.label}',
        description: isExpired
            ? 'Le diagnostic ${d.type.label} a expiré le ${_d(exp)}. '
                'À renouveler pour les futurs baux.'
            : 'Le diagnostic ${d.type.label} expire le ${_d(exp)}. '
                'Anticipe son renouvellement.',
        sourceId: d.id,
        severite: isExpired ? 2 : 1,
      ));
    }

    result.sort((a, b) => a.date.compareTo(b.date));
    return result;
  }

  /// Nombre de rappels urgents (sévérité 2) ou échéant dans 30 jours.
  int countUrgents() {
    final now = DateTime.now();
    return compute().where((r) {
      if (r.severite >= 2) return true;
      final d = r.date.difference(now).inDays;
      return d >= 0 && d <= 30;
    }).length;
  }

  static bool _inWindow(DateTime d, DateTime start, DateTime end) =>
      !d.isBefore(start) && !d.isAfter(end);

  static DateTime _subtractMonths(DateTime d, int months) {
    final m = d.month - months;
    final yearOffset = ((m - 1) ~/ 12).abs() * (m <= 0 ? -1 : 0);
    final y = d.year + (m <= 0 ? -1 - yearOffset : 0);
    final mFinal = ((m - 1) % 12 + 12) % 12 + 1;
    return DateTime(y, mFinal, d.day);
  }

  static String _d(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';
}
