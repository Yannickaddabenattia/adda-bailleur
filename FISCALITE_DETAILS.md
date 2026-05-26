# Calcul de la fiscalité — ADDA Bailleur

> Code source : `lib/services/fiscalite_service.dart`, `lib/services/sci_service.dart`, `lib/models/fiscal_settings.dart`
> Millésime : **2026** (revenus 2025)
> Régimes couverts :
> - **Location nue** : auto-détection micro-foncier / réel selon recettes
> - **LMNP** : micro-BIC 50 % (location meublée non pro)
> - **SCI à l'IR** : transparente (intégrée au foyer comme location nue, réel forcé)
> - **SCI à l'IS** : impôt société séparé (IS 15/25 %) + PFU 30 % sur dividendes distribués
> - **Hors périmètre** : LMNP réel (amortissements), LMP, monuments historiques, Malraux

---

## 1. Données d'entrée

### Par logement (statut `Location nue` requis pour entrer dans le calcul)

| Donnée | Source |
|---|---|
| **Recettes brutes** | Somme des quittances du logement sur l'année (`q.total` = loyer HC + charges encaissées) |
| **Charges déductibles (hors crédit)** | Toutes les dépenses du logement de l'année, **sauf** la catégorie « Crédit immobilier » |
| **Intérêts d'emprunt** | Issus du module Crédit (`creditService.interetsForLogementYear`) |
| **Assurance crédit** | Issus du module Crédit (`creditService.assuranceForLogementYear`) |

> ⚠️ Les intérêts et l'assurance crédit viennent **du module crédit** pour éviter la double comptabilisation (sinon une dépense « Crédit » + une mensualité crédit feraient double).

### Foyer (réglages globaux, `fiscal_settings.dart`)

| Champ | Valeur par défaut | Sens |
|---|---|---|
| `parts` | 1.0 | Nombre de parts fiscales (1 célibataire, 2 couple, +0,5 par enfant, +1 à partir du 3ᵉ enfant) |
| `marieOuPacse` | `false` | Détermine la référence du quotient familial : 1 part (célib) ou 2 parts (couple) |
| `autresRevenusBruts` | 0 | **Valeur par défaut** des revenus annuels hors fonciers (salaires, pensions…) avant abattement 10 %. Utilisée pour toute année non saisie dans `autresRevenusBrutsParAnnee` |
| `autresRevenusBrutsParAnnee` | `{}` | Map `année → montant` pour saisir une valeur précise par année (carrière qui évolue, départ retraite…). Le getter `autresRevenusBrutsPour(year)` privilégie l'entrée spécifique sur le défaut |
| `autresNichesFiscales` | 0 | Niches déjà consommées (services à la personne, dons…) — pour le plafond 10 000 € |
| `deficitsReportables` | `{}` | Map `année d'origine → montant` reportable sur 10 ans |

---

## 2. Barème IR 2026 (revenus 2025)

5 tranches **par part fiscale** :

| Tranche (€/part) | Taux |
|---|---|
| 0 — 11 497 | 0 % |
| 11 497 — 29 315 | 11 % |
| 29 315 — 83 823 | 30 % |
| 83 823 — 180 294 | 41 % |
| > 180 294 | 45 % |

Autres plafonds intégrés :
- **Quotient familial** : avantage plafonné à **1 759 € par demi-part** supplémentaire (au-delà de 1 part célibataire ou 2 parts couple)
- **Déficit foncier imputable sur revenu global** : **10 700 €/an**
- **Niches fiscales (plafond global)** : **10 000 €/an** par foyer
- **Prélèvements sociaux** : **17,2 %** sur le revenu foncier imposable

---

## 3. Auto-détection du régime (location nue : micro-foncier ou réel)

Avant tout calcul, l'app détermine automatiquement le régime applicable à
l'ensemble des logements en location nue du foyer (CGI art. 32) :

```
microFoncierEligible =
       (Σ recettes brutes des logements nus ≤ 15 000 €)
   ET  (aucun logement nu n'a un dispositif Pinel/Denormandie)
   ET  (au moins un logement nu existe)
```

- **Micro-foncier** si toutes les conditions sont réunies → abattement
  forfaitaire de **30 %** sur les recettes brutes, **aucune charge déductible**,
  **pas de déficit foncier possible**.
- **Réel** sinon → calcul détaillé (§ suivant).

> Note : Pinel et Denormandie **imposent légalement le régime réel** car ils
> ouvrent droit à des charges déductibles spécifiques. Si un seul logement nu
> bénéficie de l'un de ces dispositifs, **tout le foyer** passe au réel.

L'app affiche le régime déterminé directement sur la fiche logement (bandeau
auto), pour les statuts `Location nue` et `LMNP`. L'utilisateur ne peut pas
forcer un régime différent : la règle légale prime.

### Micro-foncier (régime simplifié)

```
revenuFoncierImposable = recettesBrutesTotales × (1 − 0,30)
                       = recettesBrutesTotales × 0,70
```

- Aucune charge ni intérêt ni assurance n'est déduit
- Aucun déficit ne peut être généré (revenu toujours ≥ 0)
- Les déficits reportables des années précédentes restent **gelés** (non
  consommés, car le micro-foncier ne les imputera pas — ils restent
  disponibles pour les futures années réelles)
- Pinel/Denormandie : **interdits** par construction → réductions = 0

---

## 4. Calcul du revenu foncier au régime réel

Pour chaque logement « Location nue », on calcule :

```
revenuNet = recettes − charges − intérêts − assuranceCrédit
```

Puis on somme **algébriquement** sur tous les logements :

```
netGlobal = Σ revenuNet  (positifs et négatifs se compensent)
```

### Cas 1 — `netGlobal ≥ 0` (bénéfice foncier)

```
revenuFoncierNetSansImputation = netGlobal
```

Le bénéfice **consomme d'abord les déficits reportables des 10 années précédentes** :

```
reportablesConsommés = min(soldeReportable, netGlobal)
revenuFoncierImposable = max(0, netGlobal − reportablesConsommés)
```

### Cas 2 — `netGlobal < 0` (déficit foncier)

Règle légale stricte : **les intérêts d'emprunt ne s'imputent pas sur le revenu global**, seulement sur les revenus fonciers futurs.

On découpe le déficit en deux parts :

```
X = recettes − charges − assuranceCrédit       (= "partie hors intérêts")
```

- **Si X ≥ 0** (le déficit vient uniquement des intérêts) :
  ```
  déficitImputableGlobal      = 0
  déficitReportableFoncier    = -netGlobal     (100 % reportable)
  ```

- **Si X < 0** (les charges hors intérêts dépassent les recettes) :
  ```
  partNonIntérêts             = -X
  imputable                   = min(partNonIntérêts, 10 700 €)
  déficitImputableGlobal      = imputable
  déficitReportableFoncier    = (partNonIntérêts − imputable) + somme intérêts
  ```

Dans tous les cas en déficit : `revenuFoncierImposable = 0`.

> Le `déficitImputableGlobal` est ensuite déduit du revenu global pour le calcul de l'IR (voir §6).
> Le `déficitReportableFoncier` est mémorisé pour les 10 années suivantes (champ `deficitsReportables`).

---

## 5. Prélèvements sociaux et LMNP

### LMNP — Loueur en Meublé Non Professionnel (micro-BIC 50 %)

Pour chaque logement dont le statut est `LMNP` :

```
revenuLmnpImposable = recettesBrutes × (1 − 0,50)
                    = recettesBrutes × 0,50
```

- Abattement forfaitaire **50 %** sur recettes brutes
- Aucune charge déductible (le 50 % couvre tout forfaitairement)
- Aucun amortissement (réservé au LMNP **réel**, non géré ici)
- **Limite : 77 700 €/an** de recettes brutes. Au-delà, le passage au BIC
  réel devient obligatoire (l'app continue à calculer le micro-BIC pour
  ne pas bloquer, mais lève le flag `lmnpDepasseSeuilMicroBIC` pour
  prévenir l'utilisateur).

### Prélèvements sociaux (17,2 %)

Les PS s'appliquent sur **l'ensemble des revenus immobiliers nets imposables** :

```
assietteImmobilier  = revenuFoncierImposable + revenuLmnpImposable
prélèvementsSociaux = assietteImmobilier × 17,2 %
```

Le LMNP non pro est assimilé à du **patrimoine immobilier privé** (et non à
une activité professionnelle), donc soumis aux mêmes prélèvements sociaux
17,2 % que les revenus fonciers.

Toujours calculés sur le **net imposable après imputations**, jamais sur les
déficits.

---

## 6. Calcul de l'IR — méthode différentielle

L'app ne calcule **pas** "IR sur foncier seul" — elle fait deux calculs IR complets du foyer et prend la différence.

### Assiettes

Les revenus fonciers nus **et** LMNP micro-BIC sont tous deux imposés au
barème progressif (IR) et donc additionnés dans l'assiette « avec immobilier ».

```
autresRevenusNets       = autresRevenusBruts × 0,9      (abattement forfaitaire 10 %)
assietteImmobilier      = revenuFoncierImposable + revenuLmnpImposable

assietteSansFoncier     = max(0, autresRevenusNets − déficitImputableGlobal)
assietteAvecFoncier     = max(0, autresRevenusNets + assietteImmobilier − déficitImputableGlobal)
```

### IR de chaque assiette (avec quotient familial)

Pour chaque assiette, on applique le **quotient familial avec plafonnement par demi-part** (voir §7) :

```
irSans  = IR(assietteSansFoncier, parts)
irAvec  = IR(assietteAvecFoncier, parts)
```

### Impôt additionnel foncier

```
impotAdditionnelFoncier  = max(0, irAvec − irSans)
```

C'est **uniquement le surplus d'IR imputable aux revenus fonciers** — pas l'IR total du foyer.

Après réduction Pinel/Denormandie (voir §9) :

```
impotAdditionnelFoncierNet = max(0, impotAdditionnelFoncier − réductionAppliquée)
```

---

## 7. Quotient familial avec plafonnement par demi-part

Implémenté dans `_impotAvecQuotientFamilial(assiette, parts)` ([fiscalite_service.dart:554](lib/services/fiscalite_service.dart)).

### Méthode officielle (administration fiscale)

1. **Calcul AVEC QF complet** :
   ```
   irAvecQf = IR(assiette / parts) × parts
   ```
   où `IR(x)` applique le barème des tranches sur `x`.

2. **Calcul de référence (sans demi-parts supplémentaires)** :
   ```
   partsRef = 2 si marié/pacsé, sinon 1
   irRef    = IR(assiette / partsRef) × partsRef
   ```

3. **Avantage du QF apporté par les demi-parts supplémentaires** :
   ```
   avantageRéel = irRef − irAvecQf
   ```

4. **Plafonnement** : `1 759 € × nb demi-parts supplémentaires`
   ```
   demiPartsSupp     = (parts − partsRef) × 2
   plafondAvantage   = demiPartsSupp × 1 759 €
   ```

5. **Décision** :
   ```
   si avantageRéel ≤ plafondAvantage :  IR final = irAvecQf       (le QF n'a pas dépassé son plafond)
   sinon                              :  IR final = irRef − plafondAvantage   (on plafonne l'avantage)
   ```

### Exemple — couple marié, 2 enfants (3 parts), assiette 60 000 €

- `partsRef = 2`, `parts = 3`, `demiPartsSupp = 2`
- `irAvecQf` : IR sur 60 000/3 = 20 000 €/part puis × 3 → l'app calcule
- `irRef` : IR sur 60 000/2 = 30 000 €/part puis × 2 → l'app calcule
- `avantageRéel = irRef − irAvecQf`
- `plafondAvantage = 2 × 1 759 = 3 518 €`
- Si `avantageRéel > 3 518 €`, on prend `irRef − 3 518 €` au lieu de `irAvecQf`

### En résumé : oui, l'app applique bien l'abattement par demi-part **et son plafonnement**

Le célibataire `parts = 1` et le couple `parts = 2` n'ont **pas de demi-part supplémentaire** → le plafond ne s'applique pas (toujours `irAvecQf`).
Le plafond ne kick in qu'à partir d'enfants ou de cas particuliers (invalidité, parent isolé, etc.).

---

## 8. Borloo Ancien (abattement sur recettes)

Conventionnement Anah — applicable aux locations nues avec convention en
cours. Trois niveaux disponibles, chacun avec un **abattement spécifique
sur les recettes brutes** du logement, **avant** la déduction des charges/
intérêts/assurance :

| Niveau | Taux d'abattement |
|---|---|
| Intermédiaire | 30 % |
| Social | 60 % |
| Très social | 70 % |

### Formule appliquée par logement (au régime réel uniquement)

```
recettesNetAbat = recettesBrutes × (1 − tauxAbattement)
revenuNet       = recettesNetAbat − charges − intérêts − assuranceCrédit
```

### Contraintes

- **Incompatible avec le micro-foncier** : le Borloo Ancien force le régime
  réel pour tout le foyer (cf. §3 — `eligibleMicroFoncier` retourne `false`
  dès qu'un logement nu a un dispositif).
- **Pas une réduction d'impôt** : l'abattement réduit la base imposable,
  pas l'IR directement. Pas de plafonnement par les niches fiscales
  (10 000 €).
- **Sélection par logement** dans le dropdown « Dispositif de
  défiscalisation » du formulaire logement. Pas de champ Pinel (date
  d'acquisition / durée / prix de revient) — mais **deux dates obligatoires** :
  - **Du** : date de début de la convention Anah
  - **Au** : date de fin (échéance de la convention)

L'abattement n'est appliqué que **si l'année calculée est comprise entre
ces deux dates** (champ `Logement.dispositifActifPour(year)`). Avant la
date de début ou après la date de fin, le logement est traité comme une
location nue classique sans abattement.

### Exemple

Logement nu, recettes 12 000 € + charges 2 000 € + intérêts 3 500 €,
Borloo Ancien social (60 %) :

```
recettesNetAbat = 12 000 × (1 − 0,60) = 4 800 €
revenuNet       = 4 800 − 2 000 − 3 500 = −700 €  → déficit foncier
```

Le déficit est traité selon les règles du §4 (intérêts non imputables sur
revenu global).

---

## 8bis. Transparence par bien (écran Fiscalité)

L'écran Fiscalité affiche le détail par bien (« DÉTAIL PAR BIEN »). Chaque
carte montre désormais explicitement :

- Le **dispositif fiscal** appliqué (Pinel/Borloo/Aucun)
- Les **recettes brutes** réelles (avant abattement)
- L'**abattement Borloo** quand applicable (ligne dédiée avec le taux et
  le montant en €)
- Les **recettes imposables** (recettes brutes − abattement)
- Les charges, intérêts, assurance crédit
- La **réduction Pinel/Denormandie** quand applicable, montrée comme
  « − X € (sur IR) » pour rappeler qu'elle vient en déduction de l'impôt
  et non du revenu

Cette section sert de pièce justificative en cas de contrôle : tu peux
recroiser les chiffres avec ce que tu déclares dans 2044 / 2044-EB.

---

## 9. Réductions Pinel / Denormandie

Pour chaque logement avec `dispositif ∈ {Pinel, Pinel+, Denormandie}` ET `dateAcquisition` renseignée :

### Base de calcul (prix de revient plafonné)

```
plafondParM²    = surface × 5 500 €/m²
plafondAbsolu   = 300 000 €
base            = min(prixRevient, plafondAbsolu, plafondParM²)
```

### Taux total selon la fenêtre Pinel

| Période | 6 ans | 9 ans | 12 ans |
|---|---|---|---|
| Acquisition ≤ 2022 | 12 % | 18 % | 21 % |
| 2023 Pinel+ | 10,5 % | 15 % | 17,5 % |
| 2023 Pinel classique | 9 % | 12 % | 14 % |
| 2024 Pinel+ | 9 % | 12 % | 14 % |
| 2024 Pinel classique | 6 % | 9 % | 10,5 % |
| ≥ 2025 | 0 % (fin du dispositif) |

**Denormandie** : aligné sur le Pinel classique de la même année, fenêtre 2019-2027.

### Réduction annuelle

```
réductionAnnuelle = (base × tauxTotal) / dureeAnnées    si l'année est dans la fenêtre d'engagement
                  = 0                                    sinon
```

> Étalement **linéaire** sur la durée d'engagement (6/9/12 ans), depuis l'année d'acquisition.

---

## 10. Plafond global des niches fiscales (10 000 €)

```
plafondRestant     = max(0, 10 000 € − autresNichesFiscales)
réductionBrute     = Σ réductionAnnuelle (tous logements)
réductionAppliquée = min(réductionBrute, plafondRestant)
```

Si tu déclares déjà 6 000 € de niches ailleurs (services à la personne…), il ne reste que 4 000 € pour le Pinel.

---

## 11. Résultat affiché — `impotAdditionnelFoncierNet + prélèvementsSociaux`

C'est cette somme qui apparaît dans la tuile « Dépenses + crédits » du dashboard, sous le nom interne `impotFoncier` ([finance_dashboard_screen.dart:156](lib/screens/finance/finance_dashboard_screen.dart)).

```
impotFoncier = max(0, irAvec − irSans − réductionAppliquée)
             + revenuFoncierImposable × 17,2 %
```

> En vue **logement unique**, `impotFoncier` est mis à 0 (la fiscalité est globale au foyer, on ne peut pas la ventiler par bien).

---

## 12. Récapitulatif : ordre exact des opérations

```
1.  Pour chaque logement « Location nue » de l'année N :
    recettes(N), charges(N), intérêts(N), assurance(N)

2.  Sommes globales :
    netGlobal = Σ (recettes − charges − intérêts − assurance)

3.  Si netGlobal < 0 → règle déficit foncier (cas 2 du §4)
    Si netGlobal ≥ 0 → cas 1 + consommation reportables

4.  revenuFoncierImposable défini

5.  PS = revenuFoncierImposable × 17,2 %

6.  autresRevenusNets = autresRevenusBruts × 0,9
    assietteSans = max(0, autresRevenusNets − déficitImputableGlobal)
    assietteAvec = max(0, autresRevenusNets + revenuFoncierImposable − déficitImputableGlobal)

7.  irSans = QF(assietteSans, parts) avec plafonnement demi-part
    irAvec = QF(assietteAvec, parts) avec plafonnement demi-part

8.  impotAdditionnelFoncier = max(0, irAvec − irSans)

9.  Pour chaque logement avec dispositif Pinel/Denormandie :
    réductionAnnuelle (étalée linéairement)

10. réductionAppliquée = min(Σ réductions, 10 000 € − autresNiches)

11. impotAdditionnelFoncierNet = max(0, impotAdditionnelFoncier − réductionAppliquée)

12. RÉSULTAT = impotAdditionnelFoncierNet + PS
```

---

## 13. SCI (Sociétés Civiles Immobilières)

Une SCI est une entité de détention nommée par l'utilisateur (écran « Mes
SCI » accessible depuis l'icône 🏛️ de la fiscalité). Chaque logement peut
être rattaché à une SCI via son champ `sciId`. Une SCI a deux régimes :

### SCI à l'IR (régime transparent)

- Les logements sont calculés **comme de la location nue au régime réel**
  (mêmes recettes, charges, intérêts, déficit foncier).
- **Le micro-foncier est désactivé** dès qu'une SCI est présente dans le
  foyer (le micro-foncier n'est ouvert qu'aux SCI familiales sous
  conditions strictes — non gérées ici par sécurité).
- Intégré au foyer fiscal personnel (apparaît dans les §3-§7).

### Bascule IR → IS (option fiscale)

La loi permet à une SCI à l'IR d'opter pour l'IS à tout moment (option
irrévocable au sens du CGI, sauf rebascule possible dans les 5 ans). Le
modèle SCI expose le champ optionnel `anneeBasculeIS: int?` :

- Si `null` (par défaut) : la SCI reste au régime initial pour toujours.
- Si renseigné : la SCI est à l'IR pour toutes les années `< anneeBasculeIS`
  et passe à l'IS à partir de `anneeBasculeIS` (inclus).

Le getter `regimeForYear(year)` calcule le régime applicable pour chaque
année, et les services `FiscaliteService.calculer()` et
`SCIService.calculerIS()` l'utilisent systématiquement. Concrètement :

- Année 2024 (avant bascule) : les logements de la SCI sont intégrés au
  foncier nu du foyer (calcul réel, déficit foncier possible).
- Année 2025 (à partir de la bascule) : la SCI calcule son IS séparément ;
  les logements sont **exclus** du foncier du foyer cette année-là et les
  suivantes.

Saisi via le formulaire « Mes SCI » → champ « Bascule à l'IS à partir de
l'année (optionnel) » (visible uniquement si le régime affiché est IR).

### SCI à l'IS (régime société)

Calcul **complètement séparé du foyer**, dans `SCIService.calculerIS()` :

```
bénéfice = max(0, recettes − charges − intérêts crédit − amortissements)

IS = bénéfice × 15 %         jusqu'à 42 500 €
   + bénéfice × 25 %         au-delà
```

- **Amortissement** : champ libre par logement (`amortissementAnnuel`),
  saisi par l'utilisateur. Représente l'amortissement linéaire du bâti
  (hors terrain) — habituellement 2 % de la valeur du bâti par an sur
  50 ans.
- Pas de prélèvements sociaux 17,2 % au niveau de la SCI (c'est l'IS qui
  remplace).
- Les logements en SCI-IS sont **exclus du calcul foncier du foyer**
  (sinon double imposition).

### Distribution de dividendes (PFU 30 %)

Si l'utilisateur saisit un montant distribué dans le formulaire SCI pour
une année donnée, on applique le **prélèvement forfaitaire unique 30 %**
(12,8 % IR + 17,2 % PS) :

```
PFU = distribution × 30 %
```

Ce montant représente l'impôt **personnel** des associés sur les
dividendes (le foyer paie déjà l'IS via la SCI).

### Total coût fiscal SCI (intégré au dashboard)

Dans le tableau de bord Finance (vue globale uniquement), le KPI
« Dépenses + crédits » inclut désormais :

```
sorties = totalDepenses
        + totalCredits
        + impotFoncier (N-1, foyer)
        + Σ (IS + PFU) des SCI à l'IS
```

---

## 14. Limites connues

- ❌ Pas de **LMNP au réel** (amortissements meublé hors SCI)
- ❌ Pas de **SCI à l'IS au réel BIC** (LMP/parahôtellerie)
- ❌ Pas de **BIC réel** quand le LMNP dépasse 77 700 € (l'app continue
  à appliquer le micro-BIC en signalant le dépassement)
- ❌ Pas de **micro-foncier pour SCI familiale** (forcé au réel par
  sécurité)
- ❌ Pas de calcul **Censi-Bouvard** ni dispositifs anciens
- ❌ Pas de gestion **multi-foyers** / quotes-parts d'associés (l'app
  considère que tu détiens 100 % des SCI)
- ✅ Auto-détection micro-foncier / réel (CGI art. 32)
- ✅ Micro-BIC LMNP 50 %
- ✅ Pinel / Pinel+ / Denormandie (avec plafonnement de niches 10 000 €)
- ✅ Quotient familial avec plafonnement par demi-part (1 759 €)
- ✅ Déficit foncier avec règle des intérêts non imputables (10 700 €)
- ✅ SCI à l'IR (transparente) et SCI à l'IS (IS 15/25 % + PFU 30 %)

