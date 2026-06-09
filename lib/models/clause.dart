import 'package:uuid/uuid.dart';

/// Catégorie d'une clause de bail (sert au regroupement dans l'UI et le PDF).
enum ClauseCategorie {
  resiliation,
  travaux,
  assurance,
  reglesDeVie,
  penalites,
  visites,
  colocation,
  garantie,
  indexation,
  charges,
  sousLocation,
  preemption,
  mediation,
  animaux,
  loyer,
  equipements,
  personnalisee;

  String get label {
    switch (this) {
      case ClauseCategorie.resiliation:
        return 'Résiliation';
      case ClauseCategorie.travaux:
        return 'Travaux';
      case ClauseCategorie.assurance:
        return 'Assurance';
      case ClauseCategorie.reglesDeVie:
        return 'Règles de vie';
      case ClauseCategorie.penalites:
        return 'Pénalités & retards';
      case ClauseCategorie.visites:
        return 'Visites & accès';
      case ClauseCategorie.colocation:
        return 'Colocation';
      case ClauseCategorie.garantie:
        return 'Garantie';
      case ClauseCategorie.indexation:
        return 'Indexation du loyer';
      case ClauseCategorie.charges:
        return 'Charges';
      case ClauseCategorie.sousLocation:
        return 'Sous-location & cession';
      case ClauseCategorie.preemption:
        return 'Droit de préemption';
      case ClauseCategorie.mediation:
        return 'Médiation';
      case ClauseCategorie.animaux:
        return 'Animaux';
      case ClauseCategorie.loyer:
        return 'Loyer & paiement';
      case ClauseCategorie.equipements:
        return 'Équipements & extérieurs';
      case ClauseCategorie.personnalisee:
        return 'Clauses personnalisées';
    }
  }
}

/// Une clause de bail. Soit issue du catalogue standard ([isCustom] = false),
/// soit rédigée librement par le bailleur ([isCustom] = true).
///
/// Les clauses sont **embarquées** dans [ContratBail] (sérialisées en Map dans
/// l'adapter Hive et le backup) : elles sont propres à chaque contrat.
class Clause {
  final String id;
  String titre;
  String contenu;
  ClauseCategorie categorie;
  bool isCustom;
  bool active;

  Clause({
    required this.id,
    required this.titre,
    required this.contenu,
    required this.categorie,
    this.isCustom = false,
    this.active = true,
  });

  factory Clause.custom({
    required String titre,
    required String contenu,
    ClauseCategorie categorie = ClauseCategorie.personnalisee,
  }) =>
      Clause(
        id: const Uuid().v4(),
        titre: titre.trim(),
        contenu: contenu.trim(),
        categorie: categorie,
        isCustom: true,
        active: true,
      );

  Clause copy() => Clause(
        id: id,
        titre: titre,
        contenu: contenu,
        categorie: categorie,
        isCustom: isCustom,
        active: active,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'titre': titre,
        'contenu': contenu,
        'categorie': categorie.name,
        'isCustom': isCustom,
        'active': active,
      };

  factory Clause.fromMap(Map<String, dynamic> m) => Clause(
        id: m['id'] as String? ?? const Uuid().v4(),
        titre: (m['titre'] as String?) ?? '',
        contenu: (m['contenu'] as String?) ?? '',
        categorie: ClauseCategorie.values.firstWhere(
          (c) => c.name == (m['categorie'] as String?),
          orElse: () => ClauseCategorie.personnalisee,
        ),
        isCustom: (m['isCustom'] as bool?) ?? false,
        active: (m['active'] as bool?) ?? true,
      );
}

/// Catalogue de clauses standards prêtes à cocher. Les `id` sont stables
/// (préfixe `cat_`) afin de retrouver l'état coché d'un bail à l'autre.
class ClauseCatalogue {
  static List<Clause> get standard => [
        Clause(
          id: 'cat_resiliation_anticipee',
          categorie: ClauseCategorie.resiliation,
          titre: 'Résiliation anticipée pour motif légitime',
          contenu:
              'Le locataire peut résilier le bail à tout moment avec un préavis '
              'réduit à un mois en cas de mutation professionnelle, perte '
              'd\'emploi, nouvel emploi consécutif à une perte d\'emploi, ou '
              'pour raison de santé constatée par certificat médical.',
        ),
        Clause(
          id: 'cat_travaux_acces',
          categorie: ClauseCategorie.travaux,
          titre: 'Accès pour travaux',
          contenu:
              'Le locataire s\'engage à autoriser l\'accès au logement pour la '
              'réalisation de travaux d\'amélioration ou de réparation '
              'nécessaires, sur préavis raisonnable du bailleur, et sans délai '
              'en cas d\'urgence (fuite, sinistre).',
        ),
        Clause(
          id: 'cat_travaux_repartition',
          categorie: ClauseCategorie.travaux,
          titre: 'Répartition des réparations',
          contenu:
              'L\'entretien courant et les réparations locatives (décret '
              'n°87-712) sont à la charge du locataire ; les grosses '
              'réparations, le gros œuvre et la mise aux normes restent à la '
              'charge du bailleur.',
        ),
        Clause(
          id: 'cat_assurance_pno',
          categorie: ClauseCategorie.assurance,
          titre: 'Assurance du locataire',
          contenu:
              'Le locataire doit être assuré contre les risques locatifs '
              '(incendie, dégâts des eaux, etc.) pendant toute la durée du bail '
              'et en justifier chaque année à la demande du bailleur.',
        ),
        Clause(
          id: 'cat_reglesvie_fumeur',
          categorie: ClauseCategorie.reglesDeVie,
          titre: 'Interdiction de fumer',
          contenu:
              'Il est interdit de fumer à l\'intérieur du logement et des '
              'parties communes privatives.',
        ),
        Clause(
          id: 'cat_reglesvie_bruit',
          categorie: ClauseCategorie.reglesDeVie,
          titre: 'Respect du voisinage',
          contenu:
              'Le locataire s\'engage à jouir paisiblement des lieux et à '
              'respecter la tranquillité du voisinage, notamment entre 22h et '
              '7h.',
        ),
        Clause(
          id: 'cat_penalites_retard',
          categorie: ClauseCategorie.penalites,
          titre: 'Frais de relance en cas de retard',
          contenu:
              'En cas de retard de paiement, des frais de relance pourront être '
              'appliqués dans les limites légales, sans préjudice de la mise en '
              'œuvre de la clause résolutoire après commandement de payer resté '
              'infructueux.',
        ),
        Clause(
          id: 'cat_visites_relocation',
          categorie: ClauseCategorie.visites,
          titre: 'Visites en cas de vente ou relocation',
          contenu:
              'En cas de vente ou de relocation, le locataire autorise les '
              'visites deux heures par jour ouvrable, selon des horaires '
              'convenus entre les parties.',
        ),
        Clause(
          id: 'cat_colocation_solidarite',
          categorie: ClauseCategorie.colocation,
          titre: 'Solidarité entre colocataires',
          contenu:
              'Les colocataires sont solidairement et indivisiblement tenus du '
              'paiement du loyer, des charges et de l\'exécution du bail.',
        ),
        Clause(
          id: 'cat_garantie_caution',
          categorie: ClauseCategorie.garantie,
          titre: 'Conditions de la caution',
          contenu:
              'Le cautionnement est consenti pour toute la durée du bail, '
              'renouvellements compris, dans la limite du montant indiqué à '
              'l\'acte de cautionnement annexé.',
        ),
        Clause(
          id: 'cat_indexation_irl',
          categorie: ClauseCategorie.indexation,
          titre: 'Révision selon l\'IRL',
          contenu:
              'Le loyer est révisé chaque année à la date anniversaire du bail '
              'selon la variation de l\'Indice de Référence des Loyers (IRL) '
              'publié par l\'INSEE, sans pouvoir excéder cette variation.',
        ),
        Clause(
          id: 'cat_charges_regularisation',
          categorie: ClauseCategorie.charges,
          titre: 'Régularisation annuelle des charges',
          contenu:
              'Les provisions sur charges font l\'objet d\'une régularisation '
              'annuelle sur justificatifs, conformément à l\'article 23 de la '
              'loi du 6 juillet 1989.',
        ),
        Clause(
          id: 'cat_souslocation_interdiction',
          categorie: ClauseCategorie.sousLocation,
          titre: 'Interdiction de sous-louer',
          contenu:
              'Toute sous-location, totale ou partielle, et toute cession du '
              'bail sont interdites sans l\'accord écrit préalable du bailleur.',
        ),
        Clause(
          id: 'cat_mediation_litige',
          categorie: ClauseCategorie.mediation,
          titre: 'Médiation préalable',
          contenu:
              'En cas de litige, les parties s\'efforceront de trouver une '
              'solution amiable, le cas échéant via la commission '
              'départementale de conciliation, avant toute action judiciaire.',
        ),

        // ─── Nouvelles clauses cat_v2_* (catalogue v2 — juin 2026) ──────
        // Résiliation / sortie
        Clause(
          id: 'cat_v2_preavis_zone_tendue',
          categorie: ClauseCategorie.resiliation,
          titre: 'Préavis réduit en zone tendue',
          contenu:
              'Si le logement est situé dans une commune classée en zone '
              'tendue (décret n°2013-392), le préavis de résiliation du '
              'locataire est ramené à un mois.',
        ),
        Clause(
          id: 'cat_v2_preavis_motif_legal',
          categorie: ClauseCategorie.resiliation,
          titre: 'Préavis réduit pour motif légal',
          contenu:
              'Le préavis du locataire est ramené à un mois en cas de '
              'mutation professionnelle, perte d\'emploi, nouvel emploi '
              'consécutif à une perte d\'emploi, bénéficiaire RSA ou AAH, '
              'état de santé, ou attribution d\'un logement social '
              '(art. 15-I de la loi du 6 juillet 1989).',
        ),
        Clause(
          id: 'cat_v2_forme_conge',
          categorie: ClauseCategorie.resiliation,
          titre: 'Forme du congé',
          contenu:
              'Le congé est notifié par lettre recommandée avec accusé de '
              'réception, par acte de commissaire de justice, ou par remise '
              'en main propre contre récépissé ou émargement.',
        ),
        Clause(
          id: 'cat_v2_restitution_cles',
          categorie: ClauseCategorie.resiliation,
          titre: 'Restitution des clés à l\'état des lieux de sortie',
          contenu:
              'Le loyer et les charges restent dus jusqu\'à la remise '
              'effective des clés au bailleur lors de l\'état des lieux de '
              'sortie.',
        ),
        // Travaux / aménagements
        Clause(
          id: 'cat_v2_embellissement_libre',
          categorie: ClauseCategorie.travaux,
          titre: 'Embellissements sans accord préalable',
          contenu:
              'Le locataire peut réaliser librement les travaux d\'embellis'
              'sement (peinture, papier peint, sols souples). Le bailleur '
              'pourra exiger une remise en l\'état si les transformations '
              'sont excessives ou ne correspondent pas à un usage normal.',
        ),
        Clause(
          id: 'cat_v2_transformation_accord',
          categorie: ClauseCategorie.travaux,
          titre: 'Transformation soumise à accord écrit',
          contenu:
              'Toute modification de la structure (cloisons, réseaux, '
              'revêtements scellés) ou changement de destination des pièces '
              'est subordonné à l\'accord écrit préalable du bailleur, à '
              'défaut duquel le bailleur peut exiger la remise en l\'état '
              'aux frais du locataire.',
        ),
        // Sous-location / usage
        Clause(
          id: 'cat_v2_interdiction_airbnb',
          categorie: ClauseCategorie.sousLocation,
          titre: 'Interdiction de location touristique',
          contenu:
              'Toute mise en location touristique du logement, même de '
              'courte durée (Airbnb, Booking, plateformes similaires), est '
              'strictement interdite et constitue un motif de résiliation '
              'judiciaire du bail.',
        ),
        // Animaux
        Clause(
          id: 'cat_v2_animaux_autorises',
          categorie: ClauseCategorie.animaux,
          titre: 'Autorisation des animaux familiers',
          contenu:
              'La détention d\'un animal familier est autorisée conformément '
              'à l\'article 10 de la loi n°70-598, sous réserve qu\'elle ne '
              'cause ni dégât au logement ni trouble de jouissance au '
              'voisinage.',
        ),
        Clause(
          id: 'cat_v2_chiens_categorie1',
          categorie: ClauseCategorie.animaux,
          titre: 'Interdiction des chiens de 1ʳᵉ catégorie',
          contenu:
              'La détention de chiens de 1ʳᵉ catégorie (chiens d\'attaque) '
              'est interdite. La détention de chiens de 2ᵉ catégorie est '
              'soumise à la production du permis de détention et de '
              'l\'assurance responsabilité civile en vigueur.',
        ),
        Clause(
          id: 'cat_v2_nac_dangereux',
          categorie: ClauseCategorie.animaux,
          titre: 'Interdiction des NAC réglementés',
          contenu:
              'La détention d\'animaux non domestiques réglementés '
              '(reptiles venimeux, primates, espèces protégées au titre de '
              'la CITES) est interdite dans le logement.',
        ),
        // Charges
        Clause(
          id: 'cat_v2_forfait_charges',
          categorie: ClauseCategorie.charges,
          titre: 'Forfait de charges (meublé)',
          contenu:
              'Les charges récupérables sont réglées par un forfait mensuel '
              'non révisable en cours de bail, conformément à l\'article '
              '25-10 de la loi du 6 juillet 1989 applicable au meublé.',
        ),
        Clause(
          id: 'cat_v2_consos_individuelles',
          categorie: ClauseCategorie.charges,
          titre: 'Consommations individuelles à la charge du locataire',
          contenu:
              'Les abonnements et consommations individuelles (électricité, '
              'gaz, eau si compteur individuel, internet) sont souscrits '
              'directement par le locataire et restent à sa charge.',
        ),
        // Loyer / paiement
        Clause(
          id: 'cat_v2_virement_mensuel',
          categorie: ClauseCategorie.loyer,
          titre: 'Paiement par virement mensuel',
          contenu:
              'Le loyer et les charges sont payables d\'avance, par '
              'virement bancaire, au plus tard le 5 du mois. Les frais '
              'bancaires éventuels restent à la charge de leur émetteur.',
        ),
        Clause(
          id: 'cat_v2_quittance_gratuite',
          categorie: ClauseCategorie.loyer,
          titre: 'Quittance gratuite à la demande',
          contenu:
              'Le bailleur transmet gratuitement une quittance de loyer au '
              'locataire qui en fait la demande, sur support papier ou, avec '
              'son accord exprès, par voie dématérialisée (art. 21 de la '
              'loi du 6 juillet 1989).',
        ),
        Clause(
          id: 'cat_v2_imputation_partiels',
          categorie: ClauseCategorie.loyer,
          titre: 'Imputation des paiements partiels',
          contenu:
              'En cas de paiement partiel, les sommes versées s\'imputent '
              'd\'abord sur les charges, puis sur les loyers les plus '
              'anciens, et enfin sur le loyer du mois courant.',
        ),
        // Assurance
        Clause(
          id: 'cat_v2_mrh_obligatoire',
          categorie: ClauseCategorie.assurance,
          titre: 'Multirisque habitation obligatoire',
          contenu:
              'Le locataire souscrit une assurance multirisque habitation '
              'couvrant les risques locatifs et la responsabilité civile, '
              'et en remet l\'attestation au bailleur à la remise des clés '
              'puis chaque année à la date anniversaire du bail.',
        ),
        Clause(
          id: 'cat_v2_defaut_assurance',
          categorie: ClauseCategorie.assurance,
          titre: 'Défaut d\'assurance : souscription par le bailleur',
          contenu:
              'À défaut d\'attestation d\'assurance produite par le '
              'locataire dans le mois suivant une mise en demeure, le '
              'bailleur pourra souscrire une assurance pour le compte du '
              'locataire et lui en répercuter la prime, majorée au plus de '
              '10 %, conformément à l\'art. 7 g) loi 89-462.',
        ),
        // Visites
        Clause(
          id: 'cat_v2_acces_controles',
          categorie: ClauseCategorie.visites,
          titre: 'Accès pour contrôles techniques périodiques',
          contenu:
              'Le locataire facilite l\'accès au logement pour les contrôles '
              'techniques périodiques obligatoires (chaudière, gaz, '
              'ramonage, détecteur de fumée), sur préavis de 48 heures '
              'sauf urgence.',
        ),
        // Colocation
        Clause(
          id: 'cat_v2_remplacement_colo',
          categorie: ClauseCategorie.colocation,
          titre: 'Remplacement d\'un colocataire sortant',
          contenu:
              'Le remplacement d\'un colocataire est subordonné à l\'accord '
              'écrit du bailleur et fera l\'objet d\'un avenant au présent '
              'bail. Le colocataire sortant reste solidairement tenu '
              'jusqu\'à l\'expiration du délai légal (6 mois après congé, '
              'loi ELAN).',
        ),
        Clause(
          id: 'cat_v2_indivisibilite_logement',
          categorie: ClauseCategorie.colocation,
          titre: 'Indivisibilité du logement',
          contenu:
              'Aucun colocataire ne dispose d\'un droit d\'usage exclusif '
              'sur une pièce déterminée du logement sans accord écrit des '
              'autres colocataires et du bailleur.',
        ),
        // Médiation
        Clause(
          id: 'cat_v2_cdc_prealable',
          categorie: ClauseCategorie.mediation,
          titre: 'Saisine préalable de la CDC',
          contenu:
              'En cas de litige relatif au montant du loyer, au dépôt de '
              'garantie ou aux charges, les parties saisissent en priorité '
              'la commission départementale de conciliation (art. 20 de la '
              'loi du 6 juillet 1989).',
        ),
        Clause(
          id: 'cat_v2_conciliation_750_1',
          categorie: ClauseCategorie.mediation,
          titre: 'Conciliation préalable (art. 750-1 CPC)',
          contenu:
              'Pour les litiges d\'un montant inférieur à 5 000 €, les '
              'parties recourent préalablement à un conciliateur de justice '
              'ou à une médiation, en application de l\'article 750-1 du '
              'Code de procédure civile.',
        ),
        // Règles de vie / copropriété
        Clause(
          id: 'cat_v2_reglement_copro',
          categorie: ClauseCategorie.reglesDeVie,
          titre: 'Respect du règlement de copropriété',
          contenu:
              'Le locataire prend connaissance des extraits du règlement '
              'de copropriété annexés au présent bail et s\'engage à les '
              'respecter (art. 3 de la loi du 6 juillet 1989).',
        ),
        Clause(
          id: 'cat_v2_troubles_voisinage',
          categorie: ClauseCategorie.reglesDeVie,
          titre: 'Troubles anormaux de voisinage',
          contenu:
              'Les troubles anormaux de voisinage répétés et constatés '
              '(mains courantes, attestations) peuvent justifier la mise en '
              'œuvre de la clause résolutoire et la résiliation judiciaire '
              'du bail.',
        ),
        Clause(
          id: 'cat_v2_notif_electronique',
          categorie: ClauseCategorie.reglesDeVie,
          titre: 'Notifications par voie électronique',
          contenu:
              'Les parties acceptent l\'envoi par courriel des quittances, '
              'attestations et avis non solennels. Les congés et mises en '
              'demeure restent toutefois notifiés sous la forme légale '
              '(LRAR ou acte de commissaire de justice).',
        ),
        // Équipements / extérieurs
        Clause(
          id: 'cat_v2_jardin_entretien',
          categorie: ClauseCategorie.equipements,
          titre: 'Entretien du jardin et des haies',
          contenu:
              'Le locataire assure l\'entretien courant du jardin : tonte '
              'régulière, taille des haies (hauteur maximale recommandée '
              '2 m), désherbage et arrosage, conformément au décret '
              'n°87-712 sur les réparations locatives.',
        ),
        Clause(
          id: 'cat_v2_piscine_entretien',
          categorie: ClauseCategorie.equipements,
          titre: 'Entretien de la piscine privative',
          contenu:
              'Le locataire assure le traitement chimique de l\'eau, le '
              'nettoyage du bassin et le maintien des dispositifs de '
              'sécurité (loi n°2003-9). Les équipements de filtration '
              'majeurs restent à la charge du bailleur.',
        ),
        Clause(
          id: 'cat_v2_fibre_optique',
          categorie: ClauseCategorie.equipements,
          titre: 'Raccordement à la fibre optique',
          contenu:
              'Le bailleur ne peut s\'opposer sans motif sérieux et '
              'légitime au raccordement du logement à la fibre optique '
              'effectué aux frais du locataire (loi n°66-457).',
        ),
        Clause(
          id: 'cat_v2_clim_pac',
          categorie: ClauseCategorie.equipements,
          titre: 'Entretien climatisation / pompe à chaleur',
          contenu:
              'Le locataire assure le nettoyage des filtres et le contrôle '
              'annuel d\'étanchéité du circuit frigorifique de la '
              'climatisation ou de la pompe à chaleur installée.',
        ),
        Clause(
          id: 'cat_v2_parking_accessoire',
          categorie: ClauseCategorie.equipements,
          titre: 'Place de stationnement accessoire',
          contenu:
              'La place de stationnement est mise à disposition pour le '
              'seul stationnement d\'un véhicule à moteur en état de '
              'marche. Tout stockage, atelier ou activité commerciale y '
              'est interdit.',
        ),
        Clause(
          id: 'cat_v2_cave_annexe',
          categorie: ClauseCategorie.equipements,
          titre: 'Cave ou local annexe',
          contenu:
              'La cave ou le local annexe est mis à disposition pour le '
              'stockage personnel non dangereux. Le stockage de matières '
              'inflammables, périssables ou polluantes y est interdit.',
        ),
      ];
}
