# Soumission Microsoft Store — ADDA Bailleur (Windows / MSIX)

> État : technique prêt (msix + CI). Bloquant = compte Partner Center + réservation du nom.
> Mis à jour : juin 2026.

---

## ÉTAPE 1 — Compte & nom (FAIT ✅)

- [x] Compte développeur Microsoft Store créé (compte individuel, gratuit).
- [x] **Nom réservé** : **ADDA Bailleur**.
- [x] Valeurs d'identité récupérées et insérées dans `pubspec.yaml` ↓
- [ ] Remplir **profil de paiement (bancaire) + profil fiscal** → *obligatoire pour vendre une app payante* (à faire avant la mise en vente).

### Identité du produit (référence)

| Champ Partner Center | Valeur | → `msix_config` |
|---|---|---|
| `Package/Identity/Name` | `ADDABENATTIA.ADDABailleur` | `identity_name` |
| `Package/Identity/Publisher` | `CN=6C9AE533-E8BE-4BA8-B763-E570011DB53E` | `publisher` |
| `Package/Properties/PublisherDisplayName` | `ADDA BENATTIA` | `publisher_display_name` |
| **Store ID** | `9PLXG3DS5KXD` | — |
| **URL Store** | https://apps.microsoft.com/detail/9PLXG3DS5KXD | — |
| **Package Family Name** | `ADDABENATTIA.ADDABailleur_7ahqcehs5w564` | — |

---

## ÉTAPE 2 — Build du MSIX (automatique, sans PC Windows)

- [ ] Valeurs d'identité insérées dans `pubspec.yaml` (plus aucun `A_REMPLIR`).
- [ ] Workflow `build-windows-store.yml` poussé sur GitHub.
- [ ] GitHub → **Actions → Build Windows Store (MSIX) → Run workflow** (ou pousser un tag `store-v1.1.0`).
- [ ] Télécharger l'artefact **`adda-bailleur-msix-store`** (le `.msix`).

---

## ÉTAPE 3 — Fiche produit & soumission (Partner Center)

- [ ] **Packages** : téléverser le `.msix`.
- [ ] **Tarification** : prix de vente + marchés (au moins France).
- [ ] **Propriétés** : catégorie (voir ci-dessous).
- [ ] **Classifications d'âge** : remplir le questionnaire IARC (app sans contenu sensible → tout public attendu).
- [ ] **Listing (fr-FR)** : titre, descriptions, mots-clés, captures (voir textes prêts à coller plus bas).
- [ ] **Politique de confidentialité** : `https://addabailleur.fr/confidentialite.html`
- [ ] **Soumettre** → certification (quelques heures à quelques jours).

---

## TEXTES PRÊTS À COLLER (fr-FR)

### Catégorie recommandée
**Business** (alternative : *Finances personnelles*).

### Description courte (≤ 200 caractères)
> La gestion locative tout-en-un, 100 % locale et chiffrée : baux, quittances, états des lieux, fiscalité. Sans abonnement, vos données restent sur votre appareil.

### Description complète
ADDA Bailleur est l'application de gestion locative conçue pour les propriétaires bailleurs français qui veulent garder le contrôle — de leurs biens comme de leurs données.

100 % LOCALE ET PRIVÉE
Aucune inscription, aucun serveur, aucun cloud obligatoire. Toutes vos données sont stockées et chiffrées sur votre appareil. Pas d'abonnement : un achat unique.

CE QUE VOUS POUVEZ GÉRER
• Logements, locataires et baux (modèles conformes à la loi française)
• États des lieux d'entrée et de sortie, avec photos et signature, comparables entre eux
• Quittances de loyer aux mentions obligatoires, envoyables par e-mail
• Révision du loyer selon l'indice IRL
• Dépôt de garantie et suivi des échéances
• Tableau de bord financier avec graphiques

UN MOTEUR FISCAL INTÉGRÉ
Comparez et simulez 12 régimes : foncier au réel, micro-foncier, LMNP (micro-BIC / réel), déficit foncier, SCI à l'IR / à l'IS, et plus — avec l'historique des barèmes.

SAUVEGARDE MAÎTRISÉE
Export / import chiffré de vos données : vous gardez vos sauvegardes là où vous le décidez.

ADDA Bailleur est un outil informatif et ne constitue pas un conseil juridique ou fiscal.

### Mots-clés / search terms (max 7)
gestion locative · bailleur · quittance de loyer · état des lieux · location immobilière · LMNP · fiscalité immobilière

### Notes de version (« What's new »)
Première version Windows d'ADDA Bailleur : gestion locative complète, 100 % locale et chiffrée.

---

## CAPTURES D'ÉCRAN
- Au moins **1** capture (1366×768 conseillé ; format paysage accepté).
- À réaliser depuis l'app Windows (récupérable une fois le build CI lancé) ou recadrées depuis les versions desktop existantes.
