import 'package:flutter/foundation.dart';

import '../core/storage/local_database.dart';
import '../data/bail_templates_system.dart';
import '../models/bail_template.dart';
import '../models/contrat_bail.dart';

/// Service de gestion des templates de baux.
///
/// Combine deux sources :
/// - Templates **système** (lecture seule) déclarés dans
///   [BailTemplatesSystem], livrés avec l'application.
/// - Templates **utilisateur** stockés dans `LocalDatabase.bailTemplatesBox`,
///   créés via le formulaire d'édition de template ou via le dialog
///   « Sauvegarder ce bail comme template ».
///
/// Garde-fous :
/// - On n'écrit **jamais** un template `isSystem = true` dans Hive.
/// - On ne supprime / n'édite **jamais** un template système.
/// - À l'import d'un backup `.adls`, on filtre `where((t) => !t.isSystem)`
///   pour ne pas dupliquer les templates système qui pourraient avoir été
///   sérialisés par erreur dans une vieille sauvegarde.
class BailTemplateService extends ChangeNotifier {
  /// Tous les templates (système puis utilisateur, triés par
  /// `dateModification` décroissante pour les user).
  List<BailTemplate> all() {
    final systemList = BailTemplatesSystem.all;
    final userList = LocalDatabase.bailTemplatesBox.values
        .where((t) => !t.isSystem)
        .toList()
      ..sort((a, b) {
        final ad = a.dateModification ?? DateTime(1970);
        final bd = b.dateModification ?? DateTime(1970);
        return bd.compareTo(ad);
      });
    return [...systemList, ...userList];
  }

  /// Templates système uniquement.
  List<BailTemplate> systemTemplates() => BailTemplatesSystem.all;

  /// Templates utilisateur uniquement.
  List<BailTemplate> userTemplates() => LocalDatabase.bailTemplatesBox.values
      .where((t) => !t.isSystem)
      .toList()
    ..sort((a, b) {
      final ad = a.dateModification ?? DateTime(1970);
      final bd = b.dateModification ?? DateTime(1970);
      return bd.compareTo(ad);
    });

  /// Recherche par ID dans les deux sources.
  /// Retourne le template système si l'ID y correspond, sinon le template
  /// utilisateur. Null si introuvable.
  BailTemplate? byId(String id) {
    final sys = BailTemplatesSystem.byId(id);
    if (sys != null) return sys;
    return LocalDatabase.bailTemplatesBox.get(id);
  }

  /// Enregistre un template utilisateur (création ou modification).
  /// Lève [ArgumentError] si on tente d'écrire un template système.
  Future<BailTemplate> save(BailTemplate t) async {
    if (t.isSystem) {
      throw ArgumentError(
        'Impossible d\'enregistrer un template système (id=${t.id}). '
        'Utilisez duplicateSystem() pour créer une copie éditable.',
      );
    }
    t.dateModification = DateTime.now().toUtc();
    await LocalDatabase.bailTemplatesBox.put(t.id, t);
    notifyListeners();
    return t;
  }

  /// Supprime un template utilisateur. Lève [ArgumentError] sur un système.
  Future<void> delete(String id) async {
    if (BailTemplatesSystem.byId(id) != null) {
      throw ArgumentError(
        'Impossible de supprimer un template système (id=$id).',
      );
    }
    await LocalDatabase.bailTemplatesBox.delete(id);
    notifyListeners();
  }

  /// Duplique un template système vers un template utilisateur éditable.
  /// Le nouveau template a un UUID, `isSystem = false`, et
  /// `sourceSystemId = systemId`.
  Future<BailTemplate> duplicateSystem(
    String systemId, {
    required String nouveauNom,
  }) async {
    final src = BailTemplatesSystem.byId(systemId);
    if (src == null) {
      throw ArgumentError('Template système introuvable : $systemId');
    }
    final user = BailTemplate.userTemplate(
      nom: nouveauNom,
      description: src.description,
      typeBail: src.typeBail,
      dureeDefautMois: src.dureeDefautMois,
      depotMultiplicateurLoyer: src.depotMultiplicateurLoyer,
      depotInterdit: src.depotInterdit,
      preavisBailleurMois: src.preavisBailleurMois,
      preavisLocataireMois: src.preavisLocataireMois,
      renouvellementTacite: src.renouvellementTacite,
      justificatifMobiliteRequis: src.justificatifMobiliteRequis,
      clausesPreCochees: src.clausesPreCochees,
      clausesPersoIncluses: src.clausesPersoIncluses,
      equipementsMeubleDefauts: src.equipementsMeubleDefauts,
      noteIntroPdf: src.noteIntroPdf,
      sourceSystemId: systemId,
    );
    await LocalDatabase.bailTemplatesBox.put(user.id, user);
    notifyListeners();
    return user;
  }

  /// Incrémente le compteur d'utilisations d'un template utilisateur.
  /// Ignoré silencieusement pour les templates système (compteur figé à 0).
  Future<void> incrementUsage(String id) async {
    if (BailTemplatesSystem.byId(id) != null) return;
    final t = LocalDatabase.bailTemplatesBox.get(id);
    if (t == null) return;
    t.nbUtilisations += 1;
    t.dateModification = DateTime.now().toUtc();
    await LocalDatabase.bailTemplatesBox.put(t.id, t);
    notifyListeners();
  }

  /// Crée un template utilisateur à partir des choix d'un bail existant.
  /// Utilisé par le dialog « Sauvegarder ce bail comme template ».
  ///
  /// Les 3 options [inclureClauses], [inclureFinancier], [inclureEquipements]
  /// pilotent ce qui est extrait du bail vers le template.
  Future<BailTemplate> createFromBail({
    required ContratBail bail,
    required String nom,
    String description = '',
    bool inclureClauses = true,
    bool inclureFinancier = false,
    bool inclureEquipements = true,
  }) async {
    final clausesIds = <String>[];
    final clausesPerso = <dynamic>[];
    if (inclureClauses) {
      for (final c in bail.clauses) {
        if (!c.active) continue;
        if (c.isCustom) {
          clausesPerso.add(c.copy());
        } else {
          clausesIds.add(c.id);
        }
      }
    }
    final template = BailTemplate.userTemplate(
      nom: nom,
      description: description,
      typeBail: bail.type,
      dureeDefautMois: bail.dureeMois,
      depotMultiplicateurLoyer: inclureFinancier && bail.loyerHC > 0
          ? (bail.depotGarantie / bail.loyerHC)
          : bail.type.plafondDepotMois.toDouble(),
      depotInterdit: bail.type == BailType.mobilite,
      preavisBailleurMois: bail.preavisBailleurMois,
      preavisLocataireMois: bail.preavisLocataireMois,
      renouvellementTacite: bail.renouvellementTacite,
      justificatifMobiliteRequis: bail.type == BailType.mobilite,
      clausesPreCochees: clausesIds,
      clausesPersoIncluses: clausesPerso.cast(),
      equipementsMeubleDefauts:
          inclureEquipements ? Map.from(bail.equipementsMeuble) : null,
    );
    await LocalDatabase.bailTemplatesBox.put(template.id, template);
    notifyListeners();
    return template;
  }
}
