import '../models/bail_template.dart';
import '../models/contrat_bail.dart';

/// Templates de baux pré-rédigés livrés avec l'application.
///
/// Source de vérité : ce fichier Dart, versionné avec git. Jamais écrit en
/// base Hive : les templates système ont `isSystem = true` et sont concaténés
/// aux templates utilisateur par `BailTemplateService.all`.
///
/// Pour modifier un template système (changement de loi, ajout de clause),
/// éditer ici puis publier une nouvelle version de l'app.
///
/// Pour ajouter un nouveau template système : ajouter une entrée dans la
/// liste ci-dessous avec un nouvel ID unique préfixé `BAIL_` (en majuscules).
class BailTemplatesSystem {
  /// Liste immuable des templates standards. L'ordre est celui d'affichage
  /// dans la galerie.
  static List<BailTemplate> get all => List.unmodifiable(_templates);

  /// Recherche par ID. Retourne null si l'ID n'est pas un template système.
  static BailTemplate? byId(String id) {
    for (final t in _templates) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Renvoie une copie indépendante (sûre à muter, ex: pour "Dupliquer").
  static BailTemplate? copyById(String id) => byId(id)?.copy();
}

final List<BailTemplate> _templates = [
  BailTemplate(
    id: 'BAIL_NU_RP_3A',
    nom: 'Bail nu — Résidence principale (3 ans)',
    description:
        'Location vide à usage de résidence principale, loi du 6 juillet '
        '1989. Durée 3 ans renouvelable tacitement, dépôt 1 mois HC.',
    typeBail: BailType.vide,
    dureeDefautMois: 36,
    depotMultiplicateurLoyer: 1.0,
    preavisBailleurMois: 6,
    preavisLocataireMois: 3,
    renouvellementTacite: true,
    clausesPreCochees: [
      'cat_resiliation_anticipee',
      'cat_travaux_repartition',
      'cat_assurance_pno',
      'cat_indexation_irl',
      'cat_charges_regularisation',
      'cat_souslocation_interdiction',
      'cat_mediation_litige',
      'cat_v2_mrh_obligatoire',
      'cat_v2_forme_conge',
    ],
    isSystem: true,
  ),

  BailTemplate(
    id: 'BAIL_MEUBLE_RP',
    nom: 'Bail meublé — Résidence principale',
    description:
        'Location meublée à usage de résidence principale (loi ALUR / loi du '
        '6 juillet 1989, art. 25-3 à 25-11). Durée 1 an renouvelable, dépôt '
        '2 mois HC. Inventaire et équipements obligatoires (décret 2015-981).',
    typeBail: BailType.meuble,
    dureeDefautMois: 12,
    depotMultiplicateurLoyer: 2.0,
    preavisBailleurMois: 3,
    preavisLocataireMois: 1,
    renouvellementTacite: true,
    clausesPreCochees: [
      'cat_resiliation_anticipee',
      'cat_travaux_repartition',
      'cat_assurance_pno',
      'cat_indexation_irl',
      'cat_souslocation_interdiction',
      'cat_mediation_litige',
      'cat_v2_mrh_obligatoire',
      'cat_v2_forfait_charges',
      'cat_v2_interdiction_airbnb',
      'cat_v2_forme_conge',
    ],
    equipementsMeubleDefauts: const {
      'literie': true,
      'volets_rideaux': true,
      'plaques_cuisson': true,
      'four_micro_ondes': true,
      'refrigerateur': true,
      'congelateur': true,
      'vaisselle': true,
      'ustensiles_cuisine': true,
      'table_sieges': true,
      'luminaires': true,
      'menage': true,
    },
    isSystem: true,
  ),

  BailTemplate(
    id: 'BAIL_ETUDIANT_9M',
    nom: 'Bail étudiant meublé (9 mois)',
    description:
        'Bail meublé étudiant, 9 mois fermes, sans tacite reconduction '
        '(loi ALUR, art. 25-7). Justificatif de scolarité requis. Dépôt 2 '
        'mois HC.',
    typeBail: BailType.meuble,
    dureeDefautMois: 9,
    depotMultiplicateurLoyer: 2.0,
    preavisBailleurMois: 3,
    preavisLocataireMois: 1,
    renouvellementTacite: false,
    clausesPreCochees: [
      'cat_travaux_repartition',
      'cat_assurance_pno',
      'cat_reglesvie_bruit',
      'cat_souslocation_interdiction',
      'cat_v2_mrh_obligatoire',
      'cat_v2_forfait_charges',
      'cat_v2_interdiction_airbnb',
      'cat_v2_forme_conge',
    ],
    equipementsMeubleDefauts: const {
      'literie': true,
      'volets_rideaux': true,
      'plaques_cuisson': true,
      'four_micro_ondes': true,
      'refrigerateur': true,
      'congelateur': true,
      'vaisselle': true,
      'ustensiles_cuisine': true,
      'table_sieges': true,
      'luminaires': true,
      'menage': true,
    },
    isSystem: true,
  ),

  BailTemplate(
    id: 'BAIL_MOBILITE',
    nom: 'Bail mobilité (1 à 10 mois)',
    description:
        'Bail meublé de courte durée, 1 à 10 mois, non renouvelable, sans '
        'dépôt de garantie (loi ELAN, art. 25-12 à 25-15). Réservé aux '
        'personnes en mobilité professionnelle, formation, mutation, stage.',
    typeBail: BailType.mobilite,
    dureeDefautMois: 6,
    depotMultiplicateurLoyer: 0,
    depotInterdit: true,
    preavisBailleurMois: 1,
    preavisLocataireMois: 1,
    renouvellementTacite: false,
    justificatifMobiliteRequis: true,
    clausesPreCochees: [
      'cat_travaux_repartition',
      'cat_assurance_pno',
      'cat_souslocation_interdiction',
      'cat_v2_mrh_obligatoire',
      'cat_v2_forfait_charges',
      'cat_v2_interdiction_airbnb',
      'cat_v2_forme_conge',
    ],
    equipementsMeubleDefauts: const {
      'literie': true,
      'volets_rideaux': true,
      'plaques_cuisson': true,
      'four_micro_ondes': true,
      'refrigerateur': true,
      'congelateur': true,
      'vaisselle': true,
      'ustensiles_cuisine': true,
      'table_sieges': true,
      'luminaires': true,
      'menage': true,
    },
    isSystem: true,
  ),

  BailTemplate(
    id: 'BAIL_COLOC_SOLIDAIRE',
    nom: 'Colocation à bail unique solidaire',
    description:
        'Colocation avec bail unique signé par tous les colocataires '
        'solidairement (loi ALUR / ELAN). Solidarité maintenue 6 mois après '
        'congé d\'un colocataire. Dépôt 1 à 2 mois HC selon nu/meublé.',
    typeBail: BailType.colocation,
    dureeDefautMois: 36,
    depotMultiplicateurLoyer: 1.0,
    preavisBailleurMois: 6,
    preavisLocataireMois: 1,
    renouvellementTacite: true,
    clausesPreCochees: [
      'cat_resiliation_anticipee',
      'cat_travaux_repartition',
      'cat_assurance_pno',
      'cat_indexation_irl',
      'cat_charges_regularisation',
      'cat_colocation_solidarite',
      'cat_souslocation_interdiction',
      'cat_mediation_litige',
      'cat_v2_mrh_obligatoire',
      'cat_v2_remplacement_colo',
      'cat_v2_indivisibilite_logement',
    ],
    isSystem: true,
  ),

  BailTemplate(
    id: 'BAIL_SAISONNIER',
    nom: 'Bail saisonnier (résidence secondaire)',
    description:
        'Location saisonnière courte durée (1 à 90 jours) hors résidence '
        'principale. Charges incluses, dépôt libre. Hors champ de la loi du '
        '6 juillet 1989 pour les locations < 90 jours.',
    typeBail: BailType.saisonnier,
    dureeDefautMois: 3,
    depotMultiplicateurLoyer: 1.0,
    preavisBailleurMois: 0,
    preavisLocataireMois: 0,
    renouvellementTacite: false,
    clausesPreCochees: [
      'cat_reglesvie_bruit',
      'cat_v2_mrh_obligatoire',
      'cat_v2_interdiction_airbnb',
      'cat_v2_jardin_entretien',
      'cat_v2_piscine_entretien',
      'cat_v2_restitution_cles',
    ],
    isSystem: true,
  ),
];
