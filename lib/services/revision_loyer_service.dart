import 'package:flutter/foundation.dart';

import '../core/storage/local_database.dart';
import '../models/logement.dart';
import '../models/revision_loyer.dart';

/// Représente un loyer effectif (HC + charges) à une date donnée.
class LoyerEffectif {
  final double loyerHC;
  final double charges;
  const LoyerEffectif({required this.loyerHC, required this.charges});
  double get total => loyerHC + charges;
}

class RevisionLoyerService extends ChangeNotifier {
  /// **Gel des loyers des passoires énergétiques.**
  /// 📚 loi n° 2021-1104 du 22/08/2021 (Climat et Résilience), art. L. 173-1-1
  /// CCH. Depuis le **24/08/2022**, aucune hausse de loyer (révision IRL ni
  /// relocation) pour un logement classé **F ou G**.
  ///
  /// Retourne un message **bloquant** si la révision est interdite, sinon
  /// `null`. Classe `null` (inconnue) → pas de blocage ici ; l'UI doit avertir
  /// séparément (cf. [dpeInconnu]).
  static String? gelRevisionError(DpeClasse? dpeClasse) {
    if (dpeClasse != null && dpeClasse.estPassoire) {
      return 'Révision de loyer interdite : logement classé ${dpeClasse.label} '
          '(passoire énergétique). Gel des loyers depuis le 24/08/2022 — '
          'loi n° 2021-1104 (Climat et Résilience), art. L. 173-1-1 CCH.';
    }
    return null;
  }

  /// `true` si la classe DPE est inconnue → l'UI doit avertir avant de réviser.
  static bool dpeInconnu(DpeClasse? dpeClasse) => dpeClasse == null;

  /// Toutes les révisions, triées de la plus récente à la plus ancienne
  /// (par date d'effet).
  List<RevisionLoyer> get all {
    final items = LocalDatabase.revisionsLoyerBox.values.toList();
    items.sort((a, b) => b.dateEffet.compareTo(a.dateEffet));
    return items;
  }

  RevisionLoyer? byId(String id) =>
      LocalDatabase.revisionsLoyerBox.get(id);

  /// Révisions d'un logement, triées chronologiquement (plus récente d'abord).
  List<RevisionLoyer> forLogement(String logementId) =>
      all.where((r) => r.logementId == logementId).toList();

  /// Loyer effectif pour [logement] au [date] donné.
  ///
  /// Recherche la révision la plus récente dont la `dateEffet` est <= [date].
  /// Si aucune révision n'est applicable (date antérieure à toutes les
  /// révisions ou aucune révision saisie), retourne le loyer de base du
  /// logement.
  LoyerEffectif loyerEffectifAt({
    required Logement logement,
    required DateTime date,
  }) {
    final revisions = forLogement(logement.id)
      ..sort((a, b) => b.dateEffet.compareTo(a.dateEffet));
    final monthStart = DateTime(date.year, date.month, 1);
    for (final r in revisions) {
      if (!r.dateEffet.isAfter(monthStart)) {
        return LoyerEffectif(loyerHC: r.loyerHC, charges: r.charges);
      }
    }
    return LoyerEffectif(
      loyerHC: logement.loyerHC,
      charges: logement.charges,
    );
  }

  Future<RevisionLoyer> add(RevisionLoyer r) async {
    await LocalDatabase.revisionsLoyerBox.put(r.id, r);
    notifyListeners();
    return r;
  }

  Future<RevisionLoyer> update(RevisionLoyer r) async {
    r.integrityHash = r.computeIntegrityHash();
    await LocalDatabase.revisionsLoyerBox.put(r.id, r);
    notifyListeners();
    return r;
  }

  Future<void> delete(String id) async {
    await LocalDatabase.revisionsLoyerBox.delete(id);
    notifyListeners();
  }

  int get count => LocalDatabase.revisionsLoyerBox.length;
}
