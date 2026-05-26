---
title: "ADDA Bailleur — Notice d'utilisation"
subtitle: "Guide complet pas-à-pas"
date: "Édition 2026"
geometry: margin=2cm
fontsize: 11pt
mainfont: "Helvetica"
toc: true
toc-depth: 2
numbersections: true
colorlinks: true
linkcolor: "#1E3A8A"
---

# Avant-propos

Bienvenue dans **ADDA Bailleur**, l'application de gestion locative qui te
permet, depuis ton téléphone, ta tablette ou ton ordinateur, de tenir
toute ta gestion immobilière sans dépendre d'un service en ligne.

Cette notice a un objectif simple : **t'expliquer chaque écran et chaque
bouton**, dans l'ordre où tu vas les rencontrer, avec des conseils
pratiques et des avertissements quand c'est nécessaire. Aucune
connaissance technique préalable n'est requise.

## Pourquoi cette app ?

- **100 % local** : tes données ne quittent jamais ton appareil. Aucun
  serveur, aucun cloud forcé, aucune fuite possible.
- **Chiffrée AES-256** : même si quelqu'un mettait la main sur ton
  téléphone et accédait au stockage, il ne pourrait rien lire sans la clé
  unique générée à l'installation.
- **Multi-plateforme** : la même app sur Mac, iPhone, iPad, Android,
  Linux. Toutes tes données sont identiques d'un appareil à l'autre via
  un système de **sauvegarde manuelle** que tu décides quand activer.
- **Conforme à la loi** : quittances loi ALUR, EDL conformes à l'article
  3-2 de la loi 89-462, contrats de bail conformes Code civil (articles
  1708 à 1762), mentions RGPD intégrées aux documents.

## Comment lire cette notice

- Les sections sont **dans l'ordre** où tu auras besoin d'elles si tu
  débutes avec l'app.
- Chaque section commence par **« Où trouver »** (le chemin dans l'app)
  puis **« À quoi ça sert »** et enfin **« Comment faire pas à pas »**.
- Les **⚠️** signalent les pièges ou les irréversibilités.
- Les **💡** sont des conseils pour gagner du temps.
- Les **📝** sont des rappels juridiques ou fiscaux importants.

---

# 1. Présentation générale

## 1.1 Ce que l'app sait faire

**Côté gestion administrative** :

- Inventorier tes **logements** (maisons, appartements, studios, garages…)
- Tenir à jour la liste de tes **locataires** et leurs coordonnées
- Réaliser des **plans 2D** de chaque logement, pièce par pièce
- Documenter l'**état du logement** (états des lieux d'entrée et de
  sortie, photos de murs intérieurs et extérieurs)
- Générer des **contrats de bail** complets (5 types : vide, meublé,
  colocation, saisonnier, mobilité)
- Créer des **avenants** (modifications du bail en cours)
- Stocker les **diagnostics obligatoires** (DPE, ERP, plomb, etc.)
- Émettre des **quittances de loyer** chaque mois, conformes à la loi
  ALUR

**Côté finances** :

- Enregistrer les **dépenses** (travaux, taxe foncière, assurance, etc.)
- Suivre les **crédits immobiliers** (capital, intérêts, mensualités,
  rachats)
- Appliquer les **révisions annuelles de loyer** selon l'IRL (INSEE)
- Calculer automatiquement la **fiscalité** (location nue, LMNP, SCI à
  l'IR, SCI à l'IS, avec Pinel, Borloo Ancien, déficit foncier,
  réductions, quotient familial…)
- Visualiser un **tableau de bord** synthétique
- Exporter ta **comptabilité en CSV** pour ton expert-comptable

**Côté communication avec le locataire** :

- **Partager** des documents (EDL, quittances) au locataire avec un
  chiffrement renforcé
- Recevoir en retour des **EDL signés** par le locataire
- Programmer des **rappels automatiques** (préavis, fin de bail,
  expiration diagnostic) avec ajout au calendrier de ton téléphone

## 1.2 Sur quels appareils ça tourne

| Appareil | Disponibilité | Particularité |
|---|---|---|
| iPhone / iPad | ✅ | AirDrop, Fichiers, calendrier natif |
| Mac (macOS) | ✅ | AirDrop, Fichiers, calendrier natif |
| Téléphone Android | ✅ | Partage Android, calendrier natif |
| Ordinateur Linux | ✅ | Le double-clic sur les fichiers `.adlb` ouvre l'app |
| Ordinateur Windows | À venir | Scaffold prêt, build à compiler |

💡 Tu peux installer l'app sur **plusieurs appareils** et les
synchroniser manuellement (cf. § 22).

## 1.3 Différence avec ADDA Locataire

Il existe une **app jumelle** appelée **ADDA Locataire**, destinée à
ton/tes locataires. Elle leur permet de recevoir les documents que tu
leur envoies, de signer un EDL, et de te faire des demandes
d'intervention. Tu ne dois **pas** installer ADDA Locataire sur ton
propre téléphone — tu utilises ADDA Bailleur. Ton locataire installe
ADDA Locataire de son côté.

---

# 2. Premier démarrage

## 2.1 Saisie du profil bailleur

Au tout premier lancement, l'app te demande de **renseigner ton
identité** :

1. **Rôle** : sélectionne « Bailleur » (propriétaire).
2. **Prénom** : ton prénom légal.
3. **Nom** : ton nom légal.
4. **Email** : une adresse fonctionnelle où tu peux recevoir des messages.
5. (Optionnel) **Téléphone**, **SIRET** si tu es en société, **mandat
   d'agence** si tu passes par un gestionnaire.

Tape sur **« Enregistrer »**.

⚠️ **Les 4 champs « rôle / prénom / nom / email » sont figés
définitivement après cette première validation.** Vérifie l'orthographe.
Cette protection évite qu'un tiers ne puisse modifier ton identité pour
émettre des quittances en ton nom.

💡 Si tu te trompes, la seule solution est de désinstaller / réinstaller
l'app (tu perds toutes tes données — fais une sauvegarde d'abord si tu
en as déjà).

## 2.2 Choix du thème (clair / sombre)

L'app détecte par défaut le thème système. Tu peux le forcer :

- **iOS / macOS** : bouton soleil/lune en bas de l'écran d'accueil
- **Android** : idem

Le mode sombre est entièrement supporté — toutes les cartes, photos et
PDF s'affichent correctement.

## 2.3 Configurer ta fiscalité (recommandé tout de suite)

Une bonne partie des calculs de l'app dépendent de tes **paramètres
fiscaux du foyer**. Renseigne-les dès maintenant pour avoir un tableau
de bord juste.

**Chemin :** `Accueil → Tableau de bord → ⚙️ Paramètres fiscaux`

Champs à remplir :

1. **Marié/pacsé** : coche si applicable. Cela définit la « part de
   référence » du quotient familial (2 si oui, 1 si célibataire).
2. **Nombre de parts fiscales** : selon ton foyer (1 célib, 2 couple,
   +0,5 par enfant à charge, +1 à partir du 3ᵉ enfant). En cas de
   doute, regarde ton dernier avis d'imposition.
3. **Valeur par défaut des revenus bruts** : revenus annuels hors
   fonciers (salaires + pensions + bénéfices). Tu peux ensuite saisir
   une **valeur précise pour chaque année** ci-dessous.
4. **Autres niches fiscales** : montant total déjà déclaré au titre
   d'autres avantages (services à la personne, dons, garde d'enfants…).
   Sert au plafonnement global de 10 000 €.

💡 Reviens ici à chaque changement de situation : naissance, mariage,
divorce, changement de salaire.

---

# 3. Mes logements

## 3.1 À quoi ça sert

Un **logement** est l'objet central de l'app : tout le reste (locataire,
EDL, bail, quittance, dépense, crédit, plan) lui est rattaché.

## 3.2 Où trouver

`Accueil → bandeau « GESTION LOCATIVE » → Mes logements`

## 3.3 Ajouter un logement

Tape sur le **bouton + flottant** en bas à droite.

### Section « Identification »

- **Libellé** : un nom court qui te parle (« Maison Cenon », « Studio
  Paris 11ᵉ »).
- **Adresse complète** : numéro + rue.
- **Code postal**.
- **Ville**.

### Section « Caractéristiques »

- **Type** : maison / appartement / studio / autre.
- **Surface habitable (m²)** : telle que mesurée loi Boutin (obligatoire
  pour les baux d'habitation).
- **Nombre de pièces** : selon la définition fiscale (pièces principales,
  hors cuisine / SDB / WC).
- **Étage** (optionnel).

### Section « Loyer et charges »

- **Loyer HC** : hors charges, mensuel.
- **Charges** : provisions mensuelles sur charges.

💡 Si le logement n'est pas loué actuellement, mets le futur loyer prévu.

### Section « Équipements »

Liste libre, séparée par des virgules. Exemples : « Chauffage gaz,
Double vitrage, Cuisine équipée, Jardin 200 m², Place de parking ».

### Section « Fiscalité »

- **Statut fiscal** :
  - **Location nue** : standard, sans meubles.
  - **LMNP** : Loueur Meublé Non Professionnel (calcul micro-BIC 50 %).
  - **SCI** : le bien est détenu par une société civile. Tu devras
    sélectionner la SCI dans le menu déroulant qui apparaît (créer la
    SCI d'abord, cf. § 16).
  - **Autre** : le bien ne génère pas de revenus fonciers (résidence
    secondaire personnelle, par exemple).

- **Régime fiscal** : **auto-détecté**, tu n'as rien à choisir. Un
  bandeau informatif t'indique le régime appliqué et pourquoi (« Recettes
  ≤ 15 000 € et aucun Pinel → Micro-foncier 30 % » par exemple).

- **Dispositif de défiscalisation** :
  - **Aucun** (par défaut).
  - **Pinel** / **Pinel+** / **Denormandie** : réductions d'impôt sur
    investissement neuf ou ancien rénové. Demande date d'acquisition,
    durée d'engagement (6/9/12 ans), prix de revient.
  - **Borloo Ancien intermédiaire (30 %)** / **social (60 %)** / **très
    social (70 %)** : abattement sur les recettes brutes via convention
    Anah. Demande **date de début et date de fin** de la convention
    (obligatoire).

- **Période de validité du dispositif** : du / au. Toute année hors de
  cette fenêtre = le dispositif n'est plus appliqué.

📝 **Loi importante** : si tu coches Pinel / Denormandie / Borloo, ton
foyer est **automatiquement basculé au régime réel**, même si tes
recettes sont sous 15 000 €. C'est une obligation légale.

### Section « SCI »

Visible uniquement si tu as choisi « SCI » dans Statut fiscal :

- **Société de détention** : choisis la SCI dans la liste. Si la liste
  est vide, l'app t'indique d'aller en créer une dans Fiscalité.
- **Amortissement annuel** (uniquement si SCI à l'IS) : montant que tu
  amortis chaque année sur le bâti (hors terrain). Habituellement 2 %
  de la valeur du bâti.

Tape sur **« Enregistrer »**.

## 3.4 Consulter la fiche d'un logement

Tape sur un logement dans la liste pour ouvrir sa **fiche détaillée**,
organisée en sections déroulantes :

1. **HERO CARD** : libellé + occupation + bilan up-to-date des
   quittances du mois.
2. **CARACTÉRISTIQUES** : surface, pièces, loyer, équipements.
3. **PLANS & SURFACES** : 0, 1 ou plusieurs plans dessinés ou importés.
4. **Photos murs / façades extérieurs** : galerie séparée.
5. **CONTRATS DE BAIL** : compteur + bail actif visible immédiatement.
6. **DIAGNOSTICS** : compteur + alerte si certains sont expirés.
7. **Locataires** : actuels et historiques.
8. **Quittances** récentes.
9. **Crédits immobiliers** rattachés.
10. **Révisions de loyer** historiques.

## 3.5 Modifier ou supprimer

- Bouton **crayon** en haut à droite : éditer.
- Bouton **poubelle** : supprimer (avec confirmation).

⚠️ La suppression d'un logement n'efface **pas** les locataires associés
(ils restent dans « Mes locataires »). En revanche, les quittances,
dépenses, crédits liés au logement seront orphelins. **Ne supprime un
logement que si tu es certain.** Préfère plutôt l'archiver (en
décochant tous les locataires actifs).

---

# 4. Plans du logement

## 4.1 À quoi ça sert

Le plan 2D te sert à :

- **Documenter visuellement** la configuration du logement.
- **Pré-remplir automatiquement les EDL** : chaque pièce dessinée
  deviendra une pièce de l'EDL, avec ses accessoires pré-cochés selon le
  type (cuisine → évier + plan de travail + plaques ; SDB → lavabo +
  douche + WC ; etc.).
- **Photographier les murs** un par un, avec horodatage.

## 4.2 Où trouver

`Fiche logement → Plans & surfaces → Gérer`

## 4.3 Créer un plan vide

Tape sur **+** → choisis :

- **Type** : Niveau (étage), Dépendance (cave, garage, dépendance), ou
  Terrain.
- **Nom** : « RDC », « 1ᵉʳ étage », « Garage », « Terrain ».

## 4.4 Importer une image en arrière-plan

Si tu as déjà un plan papier scanné :

- Tape sur **« Importer une image »**.
- Choisis le fichier (PDF / PNG / JPG).
- L'image servira d'arrière-plan ; tu dessineras les pièces par-dessus
  pour qu'elles soient cliquables.

## 4.5 Ajouter des pièces (palette rapide)

En bas de l'éditeur, tu as une **palette de boutons** :

- **Cuisine, Salon, Chambre, Suite parentale, SDB, WC, Couloir, Entrée,
  Bureau, Garage**.
- **Pièce en L** : un polygone à 6 sommets, déjà mis en forme de L.
- **Pièce en T** : un polygone à 8 sommets en T.

Tape sur le bouton → la pièce apparaît au centre du plan.

💡 La **« Suite parentale »** est traitée comme une chambre + salle de
bain attenante : les accessoires EDL combineront placards/radiateur ET
lavabo/douche/carrelage.

💡 Pour un **garage** : automatiquement, une bande orange représentant
la **porte de garage** apparaît sur le mur du bas, occupant 60 % de sa
longueur. Quand la pièce est sélectionnée, **deux poignées circulaires**
aux extrémités permettent de la redimensionner par glisser-déposer
(elle reste centrée, on l'élargit symétriquement).

## 4.6 Manipuler une pièce

- **Déplacer** : pose le doigt sur la pièce et glisse.
- **Sélectionner** : tape une fois → des poignées rouges apparaissent
  sur chaque mur.
- **Redimensionner** :
  - Pour un rectangle : tire les poignées des murs.
  - Pour un polygone (L, T) : tire les poignées des sommets pour
    déformer.
- **Rotation** : avec la pièce sélectionnée, bouton **« Rotation »** dans
  la sidebar.
- **Renommer** : double-tape sur la pièce → boîte de saisie.
- **Forme libre** : avec la pièce sélectionnée, bouton **« Forme libre »**
  → convertit en polygone, tu peux ajouter des sommets manuellement.
- **Cacher un mur** : appui long sur un mur → il devient invisible
  (utile pour des pièces qui partagent un mur).
- **Supprimer la pièce** : sélectionne + bouton poubelle.

## 4.7 Photographier les murs intérieurs

1. Active le mode **« Capture photos murs »** (icône appareil photo en
   haut).
2. Tape sur la pièce que tu veux capturer (elle se verrouille).
3. Tape sur le **numéro du mur** (M1, M2, M3, M4) qui apparaît sur
   chaque côté.
4. L'appareil photo s'ouvre.
5. Prends la photo.

Chaque photo est automatiquement :

- **Horodatée** : date + heure incrustées en bas à droite.
- **Étiquetée** : le nom de la pièce et le numéro du mur (« Salon · M2 »).
- **Hash 8 chars** (`#a1b2c3d4`) : empreinte unique de l'image.

Ces photos sont conservées avec le plan et utilisées dans l'EDL en cours.

## 4.8 Annotations

Tu peux ajouter des **marqueurs** à n'importe quel endroit du plan :

- Active le mode **« Annoter »**.
- Tape sur l'emplacement.
- Saisis un titre + une description.

Exemple : « Prise électrique défectueuse — à remplacer ».

Les annotations sont visibles sur le PDF généré.

---

# 5. Mes locataires

## 5.1 À quoi ça sert

Chaque locataire est une personne physique qui occupe (ou occupera) un
logement. Tu peux avoir :

- Un locataire seul.
- Une famille (plusieurs personnes mais 1 seul titulaire du bail).
- Une **colocation** : plusieurs titulaires du bail.

## 5.2 Où trouver

`Accueil → Mes locataires`

## 5.3 Ajouter un locataire

Bouton + flottant.

### Champs principaux

- **Prénom** + **Nom** : seront figés après création (anti-fraude).
- **Email** : figé après création. Sert au partage chiffré.
- **Téléphone**.
- **Logements rattachés** : multi-sélection. Si tu coches plusieurs,
  c'est une colocation.
- **Date d'entrée** : début effectif du bail.
- **Date de sortie** : laisse vide tant que le locataire est en place.
  Une fois renseignée, le locataire passe en « Archivé ».
- **Loyer de sortie** (à renseigner au départ) : utile en cas de
  régularisation.
- **Nouvelle adresse / téléphone / email** (après départ) : pour
  rester en contact si besoin (restitution dépôt, courrier, etc.).
- **Notes** : tout texte libre.

## 5.4 Statuts automatiques

- **Futur** : la date d'entrée est dans le futur.
- **Actif** : entre date d'entrée et sortie (ou pas de date de sortie).
- **Archivé** : date de sortie passée.

L'écran a quatre onglets : **Tous · Actifs · Futurs · Archivés**.

## 5.5 Contrats de bail signés

Sur le contrat de bail (cf. § 7), tu désigneras le ou les locataires
concernés. Un locataire peut avoir plusieurs baux successifs (sur le
même logement ou des logements différents).

---

# 6. États des lieux (EDL)

## 6.1 À quoi ça sert

L'**état des lieux** est obligatoire pour la mise en location d'un
logement nu ou meublé (article 3-2 loi 89-462). Il décrit
contradictoirement l'état du logement à l'entrée puis à la sortie. La
comparaison entre les deux permet de retenir tout ou partie du dépôt de
garantie en cas de dégradations.

## 6.2 Où trouver

`Accueil → États des lieux` ou directement depuis la fiche logement.

## 6.3 Créer un nouvel EDL

Bouton + flottant → écran de configuration :

1. **Type** : **Entrée** ou **Sortie**.
2. **Logement** : choisis dans la liste.
3. **Locataire** : choisis le locataire concerné.
4. **Date** : généralement le jour où tu fais l'EDL physiquement.

Tape sur **« Créer »**.

### Génération automatique des pièces

L'app analyse le **plan du logement** :

- Si tu as dessiné un plan avec des pièces nommées, **chaque pièce du
  plan devient une pièce de l'EDL**, dans le même ordre.
- Les **accessoires** (éléments à inspecter) sont **pré-remplis** selon
  le nom de la pièce :
  - « Cuisine » → évier, robinetterie, plan de travail, plaques de
    cuisson, four, hotte, frigo + murs/sols/plafond/éclairage.
  - « Salle de bain » → lavabo, robinetterie, baignoire/douche,
    carrelage, miroir, VMC + communs.
  - « WC » → cuvette, abattant, mécanisme + communs.
  - « Chambre » → placards, radiateur + communs.
  - « Garage » → sols, murs, plafond, éclairage, porte.
  - « Suite parentale » → placards/dressing, radiateur, lavabo,
    robinetterie, baignoire/douche, carrelage, miroir, VMC + communs.
  - Etc.

Si aucun plan n'existe, l'app utilise un **template par défaut** selon
le type de logement (studio / appartement / maison).

💡 Tu peux **modifier la liste des pièces et leurs accessoires** une
fois créée (ajouter, supprimer, renommer).

## 6.4 Saisir l'EDL pièce par pièce

Tape sur une **pièce** → liste de ses **éléments**.

Pour chaque élément :

### État

Pastille colorée à 6 niveaux :

- **Neuf** (vert foncé)
- **Bon** (bleu)
- **Usé** (orange)
- **Abîmé** (rouge)
- **Très mauvais** (rouge foncé)
- **À refaire** (rouge foncé)

### Description

Texte libre : « Tache marron 5 cm sur le mur gauche », « Joint silicone
manquant entre lavabo et meuble », etc.

### Photos

Bouton **« + Photo »** :

- Caméra ou galerie.
- L'app **incruste automatiquement** sur la photo : date, heure, et un
  hash SHA-256 de 8 caractères (`#a1b2c3d4`).
- Métadonnée stockée à part : date de capture précise + hash complet.

💡 Prends au moins 1 photo par élément en mauvais état. C'est ta preuve
en cas de litige.

## 6.5 Métadonnées globales

En bas de l'écran d'édition :

- **Adresse bailleur** : pour l'en-tête du PDF (snapshot conservé).
- **Nombre de clés** remises.
- **Relevés de compteurs** : gaz, eau chaude, eau froide, électricité
  jour, électricité nuit.
- **Notes** libres.

## 6.6 Signature

### Côté bailleur

Tape sur **« Signer (bailleur) »** → un pad de signature s'ouvre. Trace
ta signature au doigt ou au stylet. Valide.

L'app génère un **code à 8 caractères** que tu devras transmettre
**oralement** au locataire pour qu'il puisse ouvrir le fichier `.adls`
côté ADDA Locataire.

### Côté locataire

Deux options :

1. **Sur place** : le locataire signe directement sur ton appareil
   (tape sur « Signer (locataire) ») — pratique au moment de la remise
   des clés.
2. **À distance** : tu lui envoies le bundle `.adls` (cf. § 20), il
   signe dans ADDA Locataire, il te renvoie un fichier `.adlr` chiffré
   que tu ouvres pour intégrer sa signature.

## 6.7 Générer le PDF

Bouton **« Générer le PDF »** → l'app produit un document complet :

- **Couverture** avec les identités, le logement, la date.
- **Sommaire**.
- **Pièces** une par une avec leurs éléments, descriptions et **photos
  horodatées**.
- **Plans annexés** s'ils existent.
- **Signatures** propriétaire et locataire (rendu PNG).
- **Annexe photos** rassemblant toutes les photos en haute qualité.

Mention légale automatique : article 3-2 de la loi 89-462.

Le PDF s'ouvre dans le **viewer natif** : tu peux l'imprimer, l'envoyer
par mail, le partager via AirDrop, etc.

## 6.8 Retour signé locataire (`.adlr`)

Quand le locataire te renvoie un `.adlr` :

1. Tape sur le fichier reçu (mail, AirDrop, Drive…).
2. L'app s'ouvre, te demande le **code à 8 caractères** que **lui** t'a
   communiqué oralement.
3. La signature locataire s'intègre automatiquement à l'EDL.
4. L'app **vérifie le hash pré-signature** : si quelqu'un a modifié
   l'EDL entre temps, le hash diffère et l'app refuse l'intégration
   (protection anti-falsification).

---

# 7. Contrats de bail

## 7.1 À quoi ça sert

Le **contrat de bail** est le document juridique qui matérialise la
location entre toi (le bailleur) et le locataire. Il est obligatoire
(article 1714 du Code civil) et doit respecter de nombreuses règles
selon le type de location.

L'app gère **5 types de bail**, avec leurs spécificités :

| Type | Durée min | Plafond dépôt | Préavis bailleur | Préavis locataire | Quand ? |
|---|---|---|---|---|---|
| Vide | 3 ans (6 si SCI) | 2 mois HC | 6 mois | 3 mois (1 zone tendue) | Logement non meublé |
| Meublé | 1 an | 1 mois HC | 3 mois | 1 mois | Avec mobilier décret 2015-981 |
| Colocation | 3 ans | 2 mois HC | 6 mois | 1 mois | Plusieurs titulaires |
| Saisonnier | ≤ 90 jours | 1 mois | — | — | Touristique, courte durée |
| Mobilité | 1 à 10 mois | 1 mois | 1 mois | 1 mois | Étudiant, mission temporaire |

## 7.2 Où trouver

`Fiche logement → CONTRATS DE BAIL → Gérer → bouton « Nouveau bail »`

## 7.3 Créer un bail — étape par étape

### Étape A : Type de bail

Choisis dans le dropdown. **Tout le reste du formulaire s'adapte** :
durée par défaut, plafond du dépôt, préavis, clauses spécifiques.

### Étape B : Locataire(s)

Coche le ou les locataires qui signeront ce bail. Pour une colocation,
coche **plusieurs locataires**.

- Si colocation : un champ supplémentaire **« Référent colocataire »**
  apparaît. Tu peux désigner un colocataire qui sera l'**interlocuteur
  principal**.

⚠️ Si la liste est vide, c'est que tu n'as pas encore créé de locataire
pour ce logement. Va dans « Mes locataires » d'abord (§ 5).

### Étape C : Durée

- **Date d'effet** : tape sur le champ → calendrier → choisis la date.
- **Durée (mois)** : pré-remplie selon le type (36 pour vide, 12 pour
  meublé, etc.). Tu peux modifier.
- La **date de fin** est calculée automatiquement.

### Étape D : Loyer et charges

- **Loyer HC** : hors charges, pré-rempli depuis le logement.
- **Charges** : provisions mensuelles, pré-remplies depuis le logement.
- **Mode de paiement** :
  - **Virement bancaire** (le plus courant).
  - **Prélèvement automatique**.
  - **Chèque**.
  - **Espèces** (à éviter au-delà de 1 000 €).
- **RIB du bailleur** : visible si virement ou prélèvement.
- **Jour d'échéance** : 1 à 31. Habituellement le 1, 5 ou 10 du mois.
- **Dépôt de garantie** : pré-rempli au plafond légal (2 mois ou 1 mois
  HC selon le type). Tu peux mettre moins, jamais plus.

### Étape E : Clauses spécifiques

Coche / décoche selon ton choix :

- **Révision annuelle selon l'IRL** : recommandé. Permet de réviser le
  loyer chaque année selon l'indice INSEE.
- **Logement non-fumeur** : interdiction de fumer dans le logement.
- **Animaux autorisés** : si coché, un champ apparaît pour préciser les
  conditions.
- **Solidarité colocataires** (colocation uniquement) : tous les
  colocataires sont solidairement responsables du loyer entier.
  Recommandé.
- **Charges incluses** (saisonnier uniquement) : si oui, le locataire
  ne paie rien en sus.
- **Justificatif de mobilité** (mobilité uniquement) : ex « étudiant
  Master 2 à Paris-Saclay », « mission de 6 mois chez X ».

### Étape F : Équipements meublé (uniquement bail meublé)

Décret n°2015-981 du 31 juillet 2015 : la liste minimale est
**pré-cochée**. Décoche ce qui manque, ajoute via la liste « optionnels »
si tu fournis plus :

- Obligatoires : literie, table et sièges, étagères, luminaires,
  plaques, four ou micro-ondes, frigo, ustensiles, évier.
- Optionnels : lave-vaisselle, machine à laver, sèche-linge, aspirateur,
  TV.

### Étape G : Notes additionnelles

Tout texte libre que tu veux faire apparaître dans les mentions légales
du PDF.

Tape sur **« Enregistrer et ouvrir »** → tu arrives sur la **fiche du
bail**.

## 7.4 Fiche du bail

Tu y vois :

- En-tête coloré : type + statut + référence (BAIL-2026-XXX généré
  automatiquement).
- Récapitulatif (logement, durée, dates).
- Financier (loyer, charges, dépôt, mode, RIB).
- Liste des locataires avec leur statut de signature.
- État de signature bailleur.
- Bouton **« Générer / régénérer le PDF »**.
- Bouton **« Avenants »** (cf. § 8).

## 7.5 Signer le bail

### Bailleur

Tape sur **« Signer »** à côté de « Signature bailleur ». Pad de
signature. Valide.

### Locataires

Tape sur **chaque nom de locataire** dans la liste. Pad. Valide.

⚠️ En colocation, **tous** les colocataires doivent signer. Tant que
l'un manque, le bail est juridiquement incomplet.

## 7.6 Générer le PDF

Bouton **« Générer / régénérer le PDF »** :

- L'app calcule un **hash SHA-256 d'intégrité** sur 12 champs canoniques
  (id, référence, type, dates, loyer, charges, dépôt, locataires,
  signatures).
- Le PDF se génère avec :
  - Page de garde
  - Article 1 : Parties
  - Article 2 : Description du logement
  - Article 3 : Durée du bail
  - Article 4 : Loyer et charges
  - Article 5 : Obligations du bailleur
  - Article 6 : Obligations du locataire
  - Article 7 : Clauses spécifiques selon le type
  - Article 9 : Clauses générales (force majeure, litiges,
    modifications)
  - Mentions légales (loi ALUR + Code civil articles 1708-1762 + RGPD)
  - Annexe diagnostics (si tu en as ajoutés au logement)
  - Page signatures avec rendu PNG des signatures
  - Hash d'intégrité en bas

Le PDF s'ouvre directement dans le **viewer natif** pour impression /
partage.

## 7.7 Statuts du bail

L'app suit automatiquement :

- **Brouillon** : créé, pas encore signé.
- **Signé** : signature bailleur posée.
- **En cours** : entre date d'effet et fin.
- **Terminé** : après la date de fin.
- **Résilié** : forcé manuellement.

## 7.8 Imprimer en 2 exemplaires

📝 **Obligation légale** : un exemplaire pour chaque partie. Tu peux :

- **Imprimer** depuis le viewer PDF (suffit pour la signature manuelle).
- Ou **partager** le PDF au locataire qui l'imprime de son côté.

Avec les signatures électroniques de l'app + hash d'intégrité, la valeur
probante est très forte (équivalent eIDAS niveau « avancé »).

---

# 8. Avenants

## 8.1 À quoi ça sert

Un **avenant** modifie ponctuellement un bail en cours sans le rompre.
Cas typiques :

- Révision du loyer (révision IRL annuelle).
- Changement de durée (prolongation, raccourcissement).
- Ajout d'une clause (ex : nouvelle place de parking incluse).
- Départ d'un colocataire et remplacement.

## 8.2 Où trouver

`Fiche du bail → bouton « Avenants » en bas → Nouvel avenant`

## 8.3 Créer un avenant

Dialog :

- **Objet** : titre court (« Révision IRL T2 2027 », « Ajout dressing »).
- **Date d'effet** : à partir de quand l'avenant s'applique.
- **Description** : détails de la modification.
- **Modifications** (optionnelles) :
  - Nouveau loyer HC.
  - Nouvelles charges.
  - Nouvelle durée (mois).

L'app **numérote automatiquement** les avenants (#1, #2, #3…).

## 8.4 Liste des avenants

Tous les avenants d'un bail sont listés du plus récent au plus ancien,
avec les modifications affichées en chips colorées (« Loyer → 850 € »,
« Durée → 36 mois »).

📝 Comme pour le bail, un avenant doit être signé par les deux parties.

---

# 9. Diagnostics

## 9.1 À quoi ça sert

Les **diagnostics immobiliers** sont obligatoires pour louer un logement
(loi ALUR + décrets). Ils protègent le locataire et te protègent en
cas de litige.

| Diagnostic | Quand ? | Validité légale |
|---|---|---|
| DPE | Toujours | 10 ans |
| ERP | Toujours (depuis juin 2023) | 6 mois en pratique |
| Plomb | Constructions avant 1949 | Illimitée si négatif |
| Amiante | Permis avant juillet 1997 | Illimitée si négatif |
| Termites | Zones infestées | 6 mois |
| Électrique | Installation > 15 ans | 6 ans |
| Gaz | Installation > 15 ans | 6 ans |
| Assainissement | Non collectif | 3 ans |
| Audit énergétique | Passoires F/G | 5 ans |

## 9.2 Où trouver

`Fiche logement → DIAGNOSTICS → Gérer → Nouveau diagnostic`

## 9.3 Saisir un diagnostic

- **Type** : dropdown avec description explicative.
- **Date de réalisation** : date du rapport du diagnostiqueur. L'app
  calcule et affiche la **date d'expiration**.
- **Résumé / résultat** : texte court (ex : « Classe D / E pour
  l'énergie et le climat », « Conforme », « Présence plomb classe 2 »).
- **Importer le PDF** : copie le fichier dans le sandbox de l'app pour
  qu'il soit toujours accessible.

## 9.4 Diagnostics expirés

L'app **flag automatiquement** les diagnostics dont la date d'expiration
est dépassée :

- **Bordure rouge** sur la carte.
- **Alerte rouge** sur la fiche logement (« ⚠ 2 diagnostics expirés »).
- **Rappel automatique** dans l'écran Rappels (§ 18).

## 9.5 Annexe automatique au bail

À chaque génération de PDF de bail, **tous les diagnostics du logement
sont listés** dans la section « Annexes » du contrat, avec leur type,
date et statut (en cours / expiré).

---

# 10. Photos murs / façades extérieurs

## 10.1 À quoi ça sert

Documenter visuellement :

- L'état des **façades** (nord, sud, est, ouest, pignon).
- La **toiture** (visible).
- La **cour** ou le **jardin**.
- Les **clôtures**.
- Les **annexes** non incluses dans le plan principal.

Ces photos sont **distinctes** des photos d'EDL intérieures.

## 10.2 Où trouver

`Fiche logement → Photos murs / façades extérieurs`

## 10.3 Ajouter une photo

Bouton + flottant :

1. Choisis **Caméra** ou **Galerie**.
2. L'app demande un **libellé** : « Façade nord », « Pignon ouest »,
   « Toiture », « Jardin »…
3. La photo est :
   - Stockée dans le sandbox.
   - **Horodatée** (date + heure incrustées).
   - **Étiquetée** avec ton libellé.
   - Persistée dans le plan du logement (avec flag `isExterior=true`).

## 10.4 Renommer / supprimer

Sur chaque vignette :

- **Renommer** : bouton « Renommer » → modifie le libellé.
- **Supprimer** : bouton poubelle → confirmation → l'image disque est
  effacée.

---

# 11. Quittances de loyer

## 11.1 À quoi ça sert

La quittance prouve que le locataire a payé son loyer. Elle est
**obligatoire** sur demande du locataire (loi du 6 juillet 1989 article
21, dite **loi ALUR**) et il peut s'en servir comme justificatif (banque,
CAF, dossier de location futur…).

## 11.2 Où trouver

- `Accueil → bandeau FINANCES → Quittances de loyer`
- Ou raccourci « Générer quittance » sur l'accueil
- Ou bandeau d'alerte sur le tableau de bord si une quittance du mois
  manque

## 11.3 Créer une quittance

Bouton + flottant :

- **Logement** : choisis.
- **Locataire** : choisis (filtré par logement).
- **Période** : mois + année.
- **Loyer HC** + **Charges** : pré-remplis depuis le logement (ou la
  dernière révision IRL si applicable).
- **Date de paiement** : quand tu as effectivement reçu le règlement.
- **Date d'émission** : jour où tu génères la quittance.
- **Notes** (optionnel) : « Réception virement », « Acompte sur charges
  trop-perçues », etc.

Tape sur **« Enregistrer et générer le PDF »**.

## 11.4 PDF + hash

Le PDF respecte la loi ALUR (mention « Pour la somme totale de … »,
identification des parties, période, total).

Un **hash SHA-256** est inclus dans le PDF. Si quelqu'un modifie le PDF
a posteriori (par ex. pour falsifier le montant), la signature numérique
ne correspond plus et c'est détectable.

## 11.5 Génération en lot mensuelle

Sur le tableau de bord, dès qu'on entre dans un nouveau mois, l'app
détecte automatiquement les locataires actifs sans quittance pour ce
mois et affiche un bandeau **« Quittance de [mois] à générer »**. Tape
dessus → écran de création pré-rempli.

💡 Tu peux générer la quittance dès que tu reçois le règlement, ou en
fin de mois en lot, comme tu préfères.

---

# 12. Dépenses

## 12.1 À quoi ça sert

Enregistrer toutes les sorties d'argent liées à tes logements pour :

- Suivre le bilan net annuel.
- Déduire les charges du revenu foncier dans le calcul fiscal.
- Justifier en cas de contrôle fiscal.

## 12.2 Où trouver

`Accueil → Tableau de bord → bouton « Toutes les dépenses »` ou
raccourci « Ajouter dépense »

## 12.3 Saisir une dépense

- **Logement** rattaché.
- **Catégorie** : Travaux, Taxe foncière, Assurance, Frais de gestion,
  Énergie, Eau, Internet, Réparations, Honoraires, Autres. Tu peux créer
  tes propres catégories.
- **Libellé** : court (« Plombier WC », « Taxe 2026 »).
- **Montant** en €.
- **Date** : date de la facture / paiement.
- **Justificatifs** : importe la facture en PDF ou photo.
- **Notes** : libre.

📝 La catégorie **« Crédit immobilier »** est réservée au module crédit
— ne l'utilise pas pour les dépenses courantes (sinon double comptage
dans le fiscal).

## 12.4 Récap

Sur le tableau de bord :

- Total annuel de dépenses.
- Répartition par catégorie.
- Évolution mensuelle.

Toutes les dépenses sont déduites du revenu foncier (régime réel) sauf
la catégorie « Crédit immobilier ».

---

# 13. Crédits immobiliers

## 13.1 À quoi ça sert

Suivre tes emprunts immobiliers : capital, taux, échéancier, intérêts
déductibles fiscalement, rachats éventuels.

## 13.2 Où trouver

`Accueil → Tableau de bord → Crédits immobiliers → +`

## 13.3 Créer un crédit

- **Libellé** : « Crédit principal Maison Cenon ».
- **Logement** : rattachement.
- **Capital emprunté**.
- **Taux annuel** (%) : ex 1,85.
- **Durée** (mois) : ex 240 (20 ans).
- **Mensualité** : auto-calculée (peut être surchargée).
- **Assurance mensuelle**.
- **Date de début**.
- (Optionnel) **Rachat de crédit** : si tu as renégocié, saisis la date
  du rachat + la nouvelle mensualité. L'app applique le changement à
  partir de cette date.

## 13.4 Vue détaillée

- **Tableau d'amortissement** complet (capital + intérêts + assurance
  + CRD restant par mois).
- **Graphique** d'évolution.
- **Totaux** : payé YTD, intérêts YTD, capital remboursé.

## 13.5 Impact fiscal automatique

Les **intérêts** et **l'assurance crédit** sont déduits **automatiquement**
du revenu foncier dans le calcul fiscal (régime réel). Tu n'as rien à
saisir en dépense pour ça.

---

# 14. Révisions de loyer (IRL)

## 14.1 À quoi ça sert

Réviser le loyer une fois par an selon l'**Indice de Référence des
Loyers** (INSEE), si la clause est dans le bail.

## 14.2 Où trouver

`Fiche logement → Révisions de loyer → +`

## 14.3 Saisir une révision

- **Date d'effet** : généralement à la date anniversaire du bail.
- **Nouveau loyer HC** + **nouvelles charges**.
- **Motif** : « Révision IRL T2 2026 » (l'IRL est publié chaque
  trimestre par l'INSEE).

L'app calcule automatiquement le **loyer effectif** mois par mois pour
toute l'année, en tenant compte de la révision la plus récente avant
chaque mois.

## 14.4 Comment trouver le bon IRL

Site officiel INSEE : <https://www.insee.fr/fr/statistiques/serie/001515333>

Formule :
```
Nouveau loyer = Ancien loyer × (IRL nouveau / IRL ancien)
```

📝 La hausse ne peut **pas excéder** l'évolution de l'IRL sur la
période.

---

# 15. Fiscalité

## 15.1 À quoi ça sert

Calculer automatiquement chaque année l'impôt que tu dois payer au titre
des revenus fonciers, en tenant compte de :

- Toutes les recettes (quittances)
- Toutes les charges déductibles (dépenses + intérêts crédit)
- Le régime applicable (micro-foncier / réel)
- Le dispositif (Pinel, Borloo)
- Tes paramètres fiscaux foyer (parts, autres revenus)
- Les réductions Pinel/Denormandie
- Les déficits reportables
- Le quotient familial

## 15.2 Où trouver

`Accueil → Tableau de bord → bouton « Fiscalité »`

## 15.3 L'écran

- **Sélection de l'année** : flèches gauche/droite.
- **Synthèse** : revenu foncier brut, charges totales, revenu net,
  déficit éventuel, impôt additionnel + PS.
- **Détail par logement** : recettes, charges, intérêts, assurance.
- **Réductions** Pinel/Denormandie appliquées.
- **TMI** estimée.
- **Déficits reportables** consommés et restants.

## 15.4 Détail technique complet

Le calcul est documenté dans le fichier **`FISCALITE_DETAILS.md`** à la
racine du projet (24 sections détaillées).

---

# 16. SCI

## 16.1 À quoi ça sert

Gérer les biens détenus via une **Société Civile Immobilière** :

- **SCI à l'IR** : transparente, chaque associé déclare sa quote-part
  de revenus fonciers. Calcul identique à de la location nue.
- **SCI à l'IS** : la société paie son propre impôt sur les sociétés.
  Les associés ne sont imposés que sur les dividendes distribués.

## 16.2 Où trouver

`Fiscalité → icône 🏛️ (en haut à droite) → Mes SCI`

## 16.3 Créer une SCI

Bouton + flottant :

- **Nom** : « SCI Familiale Dupont ».
- **Régime** : IR (transparent) ou IS.

## 16.4 Bascule IR → IS

Une SCI initialement à l'IR peut **opter pour l'IS** à tout moment
(option irrévocable dans les 5 premières années). Pour l'enregistrer
dans l'app :

- Sur la SCI à l'IR, saisis l'**année de bascule** dans le formulaire
  d'édition.
- À partir de cette année (incluse), elle sera traitée à l'IS dans tous
  les calculs.

## 16.5 SCI à l'IS — détails

Pour chaque exercice :

- **Recettes** : somme des quittances des logements de la SCI.
- **Charges** : somme des dépenses + intérêts crédit + amortissement
  annuel (champ libre par logement).
- **Bénéfice imposable** = recettes − charges.
- **IS** = 15 % jusqu'à 42 500 € + 25 % au-delà.
- **Distribution** : montant que tu décides de distribuer aux associés
  cette année. Soumis au **PFU 30 %** (12,8 % IR + 17,2 % PS).

Tu peux saisir la distribution depuis le formulaire de la SCI, année par
année.

## 16.6 Affichage

Chaque SCI a sa card avec :

- Nom + régime appliqué cette année (badge coloré).
- Indicateur « IR → IS dès 2027 » si bascule prévue.
- Nombre de logements rattachés.
- Si IS : breakdown complet (recettes / charges / amortissement /
  bénéfice / IS / dividendes / PFU).

## 16.7 Rattacher un logement à une SCI

`Fiche logement → édition → Statut fiscal = SCI → Société de détention →
choisis la SCI`

Si SCI à l'IS, saisis aussi l'**amortissement annuel** du bâti.

---

# 17. Tableau de bord finance

## 17.1 À quoi ça sert

Une vue d'ensemble synthétique de tes finances locatives sur une année.

## 17.2 Où trouver

`Accueil → bandeau FINANCES → Tableau de bord`

## 17.3 KPI affichés

- **Encaissés** : montant total des quittances de l'année.
- **Attendus** : montant théorique selon le loyer × occupation.
- **% d'encaissement** : pourcentage.
- **En retard** : montant + nombre de quittances dues (cliquable).
- **Dépenses + crédits** annuels + moyenne mensuelle (calculée toujours
  sur 12).

## 17.4 Bilan net

```
Bilan = Recettes − (Dépenses + Crédits + Impôt foncier N-1 + IS des SCI)
```

⚠️ L'impôt foncier N-1 (de l'année précédente) est pris en compte car
c'est l'année où tu le paies effectivement.

## 17.5 Performance par logement

Liste triée par revenu attendu, avec barre de progression. Utile pour
repérer rapidement quel logement est en retard.

## 17.6 Graphique mensuel

Courbe **Réel** (encaissé) vs **Attendu** sur 12 mois.

## 17.7 Accès rapides

Boutons en bas :

- Loyers en retard
- Ajouter dépense
- Générer quittance
- Exporter bilan (sauvegarde)
- Crédits immobiliers
- Fiscalité
- Toutes les dépenses
- Mes SCI

---

# 18. Rappels et calendrier

## 18.1 À quoi ça sert

Ne plus rien oublier : préavis, fin de bail, régularisation des charges,
expiration des diagnostics. L'app scanne en permanence tes données et
te propose une **liste chronologique** de tout ce qui arrive.

## 18.2 Où trouver

`Accueil → bandeau GESTION LOCATIVE → Rappels`

## 18.3 Types de rappels auto-calculés

- **Préavis bailleur** : N mois avant la fin du bail (selon le type :
  6 mois vide, 3 meublé, 1 mobilité).
- **Préavis locataire** : idem côté locataire.
- **Fin de bail** : à la date de fin.
- **Régularisation annuelle des charges** : à la date anniversaire du
  bail.
- **Diagnostic expiré** (badge rouge) ou **proche d'expirer** (orange).

## 18.4 Sévérité

Chaque rappel a une couleur :

- **Bleu / violet** : information, échéance future.
- **Orange** : échéance dans les 30 jours ou diagnostic proche
  d'expirer.
- **Rouge** : urgent ou déjà dépassé.

## 18.5 Compteur sur l'accueil

Sur la section « Rappels » du menu Accueil :

- Total des rappels actifs.
- Nombre d'urgents (rouge) s'il y en a.

## 18.6 Ajout au calendrier natif

Sur chaque rappel, bouton **« Ajouter au calendrier »** :

- iOS / macOS : ajoute dans Calendar.app (Apple).
- Android : ajoute dans Google Agenda (ou autre app par défaut).
- Linux : non supporté nativement.

L'événement est créé à 9h le jour J, durée 1h.

---

# 19. Export comptabilité CSV

## 19.1 À quoi ça sert

Exporter toute la compta de l'année en un fichier **CSV** ouvrable dans
Excel, Numbers, Google Sheets, ou directement importable dans Indy,
Quickbooks, etc., pour ton expert-comptable.

## 19.2 Où trouver

`Accueil → bandeau FINANCES → Export comptabilité (CSV)`

## 19.3 Contenu du fichier

Format `comptabilite_<année>.csv`, délimiteur `;`, UTF-8.

Trois sections :

1. **Quittances** (recettes) : Date, Logement, Adresse, Locataire,
   Période, Notes, Total, Loyer HC, Charges, Hash.
2. **Dépenses** : Date, Logement, Catégorie, Libellé, Montant
   (négatif), Hash.
3. **Crédits immobiliers** : ligne par crédit actif l'année, total
   des mensualités annuelles.

Lignes de synthèse : Total recettes, total dépenses, **Bilan net**.

## 19.4 Partage

Le fichier généré est immédiatement proposé au partage via le
share-sheet de l'OS : mail, AirDrop, Drive…

---

# 20. Partage avec un locataire

## 20.1 À quoi ça sert

Transmettre à ton locataire de manière **chiffrée** et **traçable** :

- Les quittances qu'il peut télécharger.
- L'EDL d'entrée pour qu'il en ait une copie.
- Le contrat de bail pour son archivage.

## 20.2 Où trouver

`Accueil → bandeau FINANCES → Partager avec un locataire`

## 20.3 Workflow étape par étape

### Étape A : Que partager ?

Coche les **types de documents** :

- **Quittances**
- **États des lieux**
- **Bail** (le contrat)

### Étape B : Destinataire

Choisis le locataire dans la liste.

### Étape C : Sélection détaillée des quittances

Une section **« Quittances à inclure »** apparaît avec **toutes les
quittances de ce locataire**, dans l'ordre chronologique inverse. Toutes
sont **pré-cochées**. Tu peux :

- **Décocher individuellement** celles que tu ne veux pas envoyer.
- Cliquer sur **« Tout »** pour tout (re)cocher.
- Cliquer sur **« Aucune »** pour tout décocher.

### Étape D : Méthode de transfert

- **Bluetooth** : proche.
- **AirDrop** : iPhone/Mac entre Apple.
- **QR code** : pratique en présentiel.
- **Email** : pièce jointe.

### Étape E : Démarrer

Tape sur **« Démarrer »**.

L'app génère un fichier `.adls` chiffré contenant tout ce que tu as
coché, et un **code à 8 caractères**.

### Étape F : Communiquer le code

⚠️ Le code à 8 caractères est **affiché à l'écran**. Tu dois le
**communiquer oralement** au locataire (téléphone, SMS, en personne).
**Ne l'écris pas dans le mail** — l'intérêt du chiffrement est que le
fichier seul est inutile sans le code.

### Étape G : Le locataire reçoit

Côté ADDA Locataire, il :

- Reçoit le fichier `.adls`.
- L'ouvre dans son app.
- Saisit le code que tu lui as donné.
- Voit tes documents dans « Documents reçus ».
- Tape sur un EDL → **ouverture directe du PDF avec photos**.

---

# 21. Sauvegarde et restauration

## 21.1 Pourquoi c'est crucial

L'app ne synchronise rien sur Internet. Si tu **perds ton appareil** sans
sauvegarde, **toutes tes données sont définitivement perdues**.

**Fais une sauvegarde au moins une fois par mois.**

## 21.2 Où trouver

`Accueil → bandeau FINANCES → Sauvegarde & restauration`

## 21.3 Exporter une sauvegarde

1. Tape sur **« Exporter »**.
2. L'app te demande une **passphrase** (mot de passe long).
3. Saisis une passphrase forte : 16+ caractères, mélange lettres / chiffres
   / symboles. **NOTE-LA QUELQUE PART DE SÛR** (gestionnaire de mots de
   passe, coffre-fort).
4. L'app génère un fichier **`.adlb`** chiffré.
5. Le fichier est partagé via share-sheet : sauvegarde-le sur :
   - Ton **iCloud Drive** / Google Drive / pCloud.
   - Un **disque externe**.
   - Une **clé USB**.
   - Ton **mail** (à toi-même).

⚠️ **Sans la passphrase, le `.adlb` est irrécupérable.** Aucune
récupération possible (c'est le but du chiffrement).

## 21.4 Contenu d'un `.adlb`

**Tout** : profil bailleur, logements, plans, photos (chemins), murs
extérieurs, locataires, EDL avec photoCapturedAt, quittances, dépenses,
crédits, révisions, catégories perso, paramètres fiscaux complets,
SCI + distributions, **contrats de bail + avenants + diagnostics**.

## 21.5 Restaurer

Deux modes :

### Mode « Fusionner » (recommandé en cas de doute)

Ajoute les données du backup à celles présentes localement. Si conflit
sur un même élément (même `id`), l'app garde la version la plus récente
(comparaison `updatedAt`).

### Mode « Restaurer » (= remplacer)

⚠️ **Destructif** : efface **TOUT** localement et remplace par le
backup. Utile sur un nouvel appareil ou pour repartir d'un état propre.

### Procédure

1. Tape sur **« Restaurer une sauvegarde »**.
2. Choisis le `.adlb`.
3. Saisis la passphrase.
4. Choisis Fusion ou Restaurer (l'app demande confirmation).

## 21.6 Dossier « ADDA Bailleur document »

Les `.adlb` que tu reçois de l'extérieur (ou tes propres exports
archivés) sont stockés dans un dossier nommé **« ADDA Bailleur
document »** :

- iOS / macOS : visible dans l'app **Fichiers**.
- Android : `Android/data/com.addabenattia.addalocation/files/ADDA Bailleur document/`.

L'app conserve les **10 derniers** backups en FIFO (le 11ᵉ écrase le 1ᵉʳ).

---

# 22. Synchronisation entre appareils

## 22.1 Le principe

Aucune sync automatique : chaque appareil a sa propre base chiffrée. Tu
décides quand et comment synchroniser.

## 22.2 Méthode recommandée

1. Désigne **un appareil principal** (le plus pratique à utiliser au
   quotidien, par exemple ton Mac).
2. Quand tu fais des modifications importantes (saisie d'un nouveau
   bail, génération PDF, etc.), **exporte un `.adlb`** depuis cet
   appareil.
3. Transfère le `.adlb` aux autres appareils :
   - iPhone : AirDrop, Mail, Drive.
   - Autre Mac : AirDrop.
   - Téléphone Android : Drive, pCloud, transfert USB.
4. Sur chaque autre appareil, **« Restaurer une sauvegarde »** en mode
   **Remplacer**.

Ainsi tous les appareils sont identiques après chaque sync.

💡 **Évite la fusion à long terme** entre appareils qui divergent ; ça
peut créer des doublons ou perdre des modifications selon les
`updatedAt`. Préfère un appareil maître + replace sur les autres.

---

# 23. Sécurité et confidentialité

## 23.1 Chiffrement local

Toutes les données stockées par l'app sont **chiffrées AES-256** avec
une clé unique générée à l'installation :

- **iOS / macOS** : la clé est dans le **Keychain** d'Apple (impossible
  à extraire sans le mot de passe de session).
- **Android** : la clé est dans le **Keystore** (HSM matériel sur les
  appareils récents).
- **Linux / Windows** : fichier protégé par les permissions
  utilisateur.

Si quelqu'un récupère ton téléphone et accède au stockage brut, il ne
verra que du chiffré illisible.

## 23.2 Chiffrement des fichiers d'échange

| Fichier | Sens | Algorithme |
|---|---|---|
| `.adlb` | Backup complet | AES-GCM + PBKDF2 200 000 iter |
| `.adls` | Partage locataire | AES-GCM + PBKDF2 200 000 iter |
| `.adlr` | Retour signature | AES-GCM + PBKDF2 200 000 iter |
| `.adli` | Demande intervention | AES-GCM + PBKDF2 200 000 iter |

Tous ces fichiers commencent par le **magic byte « ADLB »** pour être
identifiés comme produits par ADDA.

## 23.3 Aucune transmission Internet

L'app ne contacte **aucun serveur**. Tous les échanges entre tes
appareils ou avec le locataire se font via les mécanismes de partage de
l'OS (AirDrop, Bluetooth, Mail, Drive, USB).

## 23.4 Tes obligations RGPD

En tant que bailleur, tu collectes des **données personnelles** de tes
locataires. Tu es **responsable du traitement** au sens du RGPD :

- Tu dois pouvoir leur fournir un **export** de leurs données sur
  demande (utilise « Partager avec un locataire » pour leur envoyer
  leur dossier complet).
- Tu dois **supprimer** leurs données 5 ans après la fin du bail
  (obligation fiscale parallèle).
- Tu ne dois **pas transmettre** leurs coordonnées à des tiers non
  autorisés.
- Tu dois conserver les données de manière **sécurisée** — l'app le
  fait pour toi avec le chiffrement AES-256.

Les mentions RGPD obligatoires sont déjà incluses dans le PDF de bail
généré par l'app.

---

# 24. Foire aux questions

## J'ai oublié ma passphrase de sauvegarde, comment récupérer ?

Impossible. C'est le but du chiffrement. Recommence à zéro depuis tes
autres appareils si tu en as.

## Mon iPhone est cassé, comment récupérer mes données ?

Si tu avais une sauvegarde `.adlb` sur iCloud ou un autre appareil :
installe l'app sur un nouvel iPhone, « Restaurer une sauvegarde », tu
récupères tout.

## Sans sauvegarde : 0 récupération.

## Puis-je avoir l'app sur mon Mac ET mon iPhone ?

Oui. Synchronise manuellement avec un `.adlb` (cf. § 22).

## Comment imprimer un contrat de bail ?

Génère le PDF (bouton « Générer/régénérer le PDF »). Le viewer natif
s'ouvre. Bouton imprimer en haut.

## Le locataire ne reçoit pas mon `.adls` par email

- Vérifie qu'il a bien ADDA Locataire installée.
- Demande-lui d'ouvrir la pièce jointe → l'app s'ouvre normalement.
- Sinon, transmets le fichier via Drive ou USB.

## Les diagnostics sont en rouge sur la fiche logement

C'est qu'ils sont **expirés**. Va dans Diagnostics → édite ou ajoute un
nouveau diagnostic à jour.

## Le calcul d'impôt foncier me semble bizarre

Vérifie tes paramètres fiscaux (parts, autres revenus). La doc complète
du calcul est dans `FISCALITE_DETAILS.md`.

## Comment ajouter une catégorie de dépense personnalisée ?

Lors de la création d'une dépense, dans le dropdown des catégories :
option « + Ajouter une catégorie ».

## L'app rame sur les gros logements (> 100 EDL)

L'app est optimisée pour ~1000 entrées par type. Au-delà, considère
archiver les anciens EDL (export `.adlb` + suppression locale).

---

*Fin de la notice d'utilisation.*

*Pour la documentation technique du calcul fiscal détaillé,*
*voir le fichier `FISCALITE_DETAILS.md` à la racine du projet.*

*ADDA Bailleur — édition 2026.*
