# Audit de conformité légale — Documents FRANÇAIS (ADDA Bailleur)

> Audit **lecture seule** réalisé le 10/06/2026. Aucune modification du code, aucun commit.
> Aucun fichier Belgique (`belgium*.dart`) ni Suisse (`switzerland*.dart`) touché.
> Verdicts : ✅ CONFORME · ⚠️ PARTIEL · ❌ NON CONFORME / ABSENT.

---

## A. BAIL (nu / meublé / mobilité)
📚 Loi n° 89-462 du 06/07/1989, art. 3 ; décret n° 2015-587 du 29/05/2015 (contrat type).

| Point | Verdict | Constat (fichier:ligne) |
|---|---|---|
| A1 Structure contrat-type (rubriques I–XI) | ❌ NON CONFORME | `contrat_bail_pdf.dart:751-753` — sections « Article 7… » propres à l'app, pas la structure I→XI du décret 2015-587. |
| A2 Mentions obligatoires | ⚠️ PARTIEL | Présents : identité, dateDébut/durée (`contrat_bail.dart:184`), surface/nbPièces, loyer, dépôt. ABSENTS : dernier loyer du précédent locataire (aucun champ), trimestre de référence IRL, période de construction, honoraires. |
| A3 Surface habitable bloquante | ⚠️ PARTIEL | Champ requis (`contrat_bail.dart:178`, constructeur :309). MAIS libellé « (loi Boutin) » (`contrat_bail_pdf.dart:324-325`) = surface de vente, pas la surface habitable loi 89-462 art. 3-1 ; clause « inexactitude > 5 % » absente. |
| A4 Notice officielle (arrêté 29/05/2015) | ❌ NON CONFORME | `contrat_bail_annexes_pdf.dart:240-244` — « Cette notice résume… » = résumé maison, pas le texte officiel. |
| A5 Encadrement des loyers (réf. majorée, complément) | ❌ ABSENT | Aucun champ `loyerReference`/`complement`/`encadrement` dans `contrat_bail.dart` ni le PDF. |
| A6 Classe DPE affichée + blocage G | ❌ ABSENT | Aucun `dpeClasse`, aucun affichage ni blocage dans le bail. |
| A7 Bail mobilité (durée, dépôt 0, solidarité) | ⚠️ PARTIEL | Durée 1–10 mois non renouvelable OK (`contrat_bail_pdf.dart:753-757`). Dépôt : plafond 0 (`contrat_bail.dart:64`) mais non forcé/masqué dans le form (défaut 0 éditable, `contrat_bail_form_screen.dart:126-127`). Exclusion de la clause de solidarité non garantie. |

## B. ÉTAT DES LIEUX
📚 Décret n° 2016-382 du 30/03/2016 ; loi 89-462 art. 3-2 et 7.

| Point | Verdict | Constat (fichier:ligne) |
|---|---|---|
| B1 Contenu minimal | ⚠️ PARTIEL | Compteurs OK (`etat_des_lieux_pdf.dart:1168-1171`), fiche/pièce OK (:166), signatures OK (:250). Clés = simple comptage (:1180), pas la destination des clés. Domicile des parties absent. |
| B2 EDL de sortie (nouveau domicile, date EDL entrée) | ❌ ABSENT | Aucune mention « nouveau domicile » ni report de la date d'EDL d'entrée. |
| B3 Forme (exemplaire / dématérialisé) | ✅ CONFORME | Signatures des 2 parties + SHA-256 (`etat_des_lieux_pdf.dart:263-277`). |
| B4 Droit de complément 10 jours | ❌ ABSENT | Aucune mention. |
| B5 Vétusté / usure normale | ❌ ABSENT | Aucune mention. |

## C. QUITTANCE
📚 Loi 89-462, art. 21.

| Point | Verdict | Constat (fichier:ligne) |
|---|---|---|
| C1 Gratuite / sur demande | ❌ ABSENT | Mention non présente dans `quittance_pdf.dart`. |
| C2 Ventilation loyer / charges | ✅ CONFORME | `quittance_pdf.dart:364-365`. |
| C3 Paiement partiel → reçu (pas quittance) | ❌ NON CONFORME | Document toujours titré « Quittance » (`quittance_pdf.dart:113`) ; pas de document « reçu » distinct, simple mention au :415-416. |
| C4 Dématérialisation = accord exprès | ❌ ABSENT | Aucune case/clause de consentement. |

## D. DÉPÔT DE GARANTIE
📚 Loi 89-462, art. 22 (nu) et 25-6 (meublé) ; loi ELAN (mobilité).

| Point | Verdict | Constat (fichier:ligne) |
|---|---|---|
| D1 Plafonds (1/2/0) affichés | ⚠️ PARTIEL | Validateur OK (`contrat_bail.dart:55-64`) + mention plafond (`contrat_bail_pdf.dart:378`) ; règle par type pas explicitée dans le doc. |
| D2 Restitution 1/2 mois + 10 %/mois | ⚠️ PARTIEL | Restitution mentionnée (`contrat_bail_pdf.dart:375-378`) ; délais 1/2 mois et majoration 10 % non explicités. |

## E. ACTE DE CAUTION ⚠️ (critique)
📚 Loi 89-462 art. 22-1 (v. 01/01/2022, ord. 2021-1192) ; art. 2297 Code civil — à peine de nullité.

| Point | Verdict | Constat (fichier:ligne) |
|---|---|---|
| E1 Montant du loyer + révision dans l'acte | ❌ ABSENT | `contrat_bail_annexes_pdf.dart:542-567` — le modèle ne reprend ni le loyer ni ses conditions de révision. |
| E2 Reproduction de l'avant-dernier alinéa art. 22-1 | ❌ ABSENT | Non reproduit. |
| E3 Mention apposée par la caution (zone vide) | ❌ NON CONFORME (NULLITÉ) | Modèle pré-rempli (:542-567) + texte « sans mention manuscrite obligatoire » fondé sur ELAN 2018 (:538-540) — dépassé par l'ordonnance 2021-1192. Cite art. 2288 (:535) au lieu de 2297. |
| E4 Remise d'un exemplaire du bail à la caution | ❌ ABSENT | Aucune mention/case. |
| E5 Blocage cumul GLI + caution | ❌ ABSENT | Aucun champ « assurance loyers impayés ». |

---

## Écarts classés

### 🔴 BLOQUANT (nullité / illégalité du document)
1. **Acte de caution (E1–E3)** : modèle pré-rempli + « sans mention manuscrite » + art. 2288 → acte NUL au regard de l'art. 22-1 (v. 2022) / art. 2297 C. civ.
2. **Notice d'information (A4)** : résumé maison au lieu du texte officiel → mention obligatoire non valable.
3. **DPE classe G — pas de blocage (A6)** : génération d'un bail pour un bien interdit à la location depuis le 01/01/2025.

### 🟠 IMPORTANT
A2 dernier loyer du précédent locataire + trimestre IRL · A5 encadrement des loyers · A7 dépôt mobilité non forcé à 0 + solidarité · B1 domicile des parties · B2 EDL sortie · B4 complément 10 j · C3 reçu partiel · C4 accord dématérialisation · D2 délais + 10 % · E4/E5 caution.

### 🟡 COSMÉTIQUE
A3 libellé « loi Boutin » → « surface habitable » · A1 structure rubriques I→XI · B5 mention vétusté · D1 règle de plafond explicite.

---

## Plan de correction proposé (NON exécuté — accord requis)
1. **Caution (priorité 1)** : retirer le modèle pré-rempli ; insérer une zone vide où la caution écrit elle-même sa mention (montant en principal + accessoires) ; reproduire l'avant-dernier alinéa de l'art. 22-1 + rappeler art. 2297 ; reprendre loyer + révision depuis le bail ; case « exemplaire du bail remis à la caution » ; blocage du cumul GLI (nouveau champ `assuranceLoyersImpayes` + exception étudiant/apprenti).
2. **Notice (A4)** : embarquer le texte officiel de l'arrêté du 29/05/2015 en vigueur (asset texte) au lieu du résumé.
3. **DPE (A6)** : ajouter `dpeClasse` (nouvel index Hive, nullable) + blocage génération si G + affichage classe.
4. **Encadrement (A5)** : champs loyer de référence majoré / complément, activables par commune (question si commune inconnue).
5. **Mobilité (A7)** : forcer/masquer le dépôt à 0 + exclure la clause de solidarité.
6. **EDL (B1-B5)** : domicile des parties, bloc sortie (nouveau domicile + date EDL entrée), mention complément 10 j, mention vétusté/usure normale, destination des clés.
7. **Quittance (C1/C3/C4)** : mention gratuité/sur demande ; document « Reçu » distinct pour paiement partiel ; case d'accord pour l'envoi dématérialisé.
8. **A2/A3/D2** : dernier loyer précédent + trimestre IRL ; libellé « surface habitable » + clause 3-1 ; délais 1/2 mois + majoration 10 %.

> Toutes ces corrections seraient strictement côté France (modèles/PDF/form/contrat_bail), avec mise à jour des tests — sans toucher BE/CH.

---

## Périmètre
✅ Audit en lecture seule. Aucun fichier Belgique ni Suisse touché. Aucun commit effectué.
