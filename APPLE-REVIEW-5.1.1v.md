# App Review — Réponse au rejet Guideline 5.1.1(v) (suppression de compte)

App : **ADDA Bailleur** · Version **1.1.0** · Build **6**
Submission rejetée : `a50b2907-7e3b-434a-b221-06ac89868934`
Correctif : option « Supprimer mon compte » (Réglages → Compte), app 100 % locale (aucun Firebase / serveur).

---

## 1. VIDÉO À FILMER (sur iPhone — le rejet est iOS)

Filmer l'écran de l'iPhone (Réglages iOS → Centre de contrôle → Enregistrement d'écran),
app **ADDA Bailleur** ouverte avec un profil et quelques données visibles :

1. App ouverte sur l'accueil (on voit qu'un compte/profil existe).
2. Aller dans **Réglages** (onglet).
3. Descendre jusqu'à la section **COMPTE** → taper **« Supprimer mon compte »**.
4. Montrer le **dialogue de confirmation** (laisser lire « action définitive et irréversible »).
5. Taper **« Supprimer définitivement »** → l'indicateur de chargement apparaît.
6. L'app revient à l'**écran de création de profil (onboarding)** → compte supprimé.
7. (Preuve) Repasser dans l'app : toujours sur l'onboarding, **aucune donnée** restante.

→ Garder la vidéo courte (~30–45 s). L'ajouter en **pièce jointe** dans
App Store Connect → *Vérification de l'app* → **Notes de l'App Review**,
et la mentionner dans la réponse au reviewer.

⚠️ Avant de filmer : ne pas être lié à ton vrai dossier cloud partagé (sinon la
suppression efface aussi ces sauvegardes). Filmer avec des données de test.

---

## 2. NOTES DE L'APP REVIEW (champ « Notes »)

### Version anglaise (recommandée pour Apple)

```
Account deletion (Guideline 5.1.1(v)):

ADDA Bailleur is a 100% local app. There is no server account and no Firebase:
all data is stored locally and encrypted on the device. What can be created is a
local profile, optionally protected by a master password for encrypted backups
the user places in their own cloud folder.

Users can permanently delete their account entirely within the app:
Settings ("Réglages") → Account ("Compte") → "Delete my account"
("Supprimer mon compte").

After an explicit confirmation, this irreversibly deletes:
- the user profile,
- all app data (properties, tenants, rent receipts, inventories, documents),
- the master password,
- the encrypted backups stored in the user's linked cloud folder.

The app then returns to the initial onboarding screen. No email, phone call or
support contact is required. A screen recording is attached.
```

### Version française

```
Suppression de compte (Guideline 5.1.1(v)) :

ADDA Bailleur est une application 100 % locale. Il n'y a aucun compte serveur ni
Firebase : toutes les données sont stockées localement et chiffrées sur
l'appareil. L'utilisateur crée un profil local, éventuellement protégé par un
mot de passe maître pour les sauvegardes chiffrées qu'il dépose dans son propre
dossier cloud.

L'utilisateur peut supprimer définitivement son compte entièrement dans l'app :
Réglages → Compte → « Supprimer mon compte ».

Après une confirmation explicite, cela efface de façon irréversible :
- le profil utilisateur,
- toutes les données (biens, locataires, quittances, états des lieux, documents),
- le mot de passe maître,
- les sauvegardes chiffrées du dossier cloud lié.

L'app revient ensuite à l'écran d'accueil initial. Aucun email, appel ni contact
support n'est nécessaire. Une vidéo d'écran est jointe.
```

---

## 3. RÉPONSE AU REVIEWER (Centre de résolution)

### Version anglaise

```
Hello, thank you for the review.

We have addressed Guideline 5.1.1(v). Note that the app is 100% local and does
not use Firebase or any server-side account — all data is stored and encrypted
on the device.

In build 6 (version 1.1.0), users can permanently delete their account from
within the app: Settings ("Réglages") → Account ("Compte") → "Delete my account"
("Supprimer mon compte"). After confirmation, this permanently deletes the user
profile, all local data, the master password, and the encrypted backups stored
in the user's linked cloud folder, then returns to the onboarding screen. No
email or support contact is required.

A screen recording of the full flow is attached in the App Review notes.
Thank you.
```

### Version française

```
Bonjour, merci pour la vérification.

Nous avons traité la Guideline 5.1.1(v). À noter : l'application est 100 % locale
et n'utilise pas Firebase ni aucun compte serveur — toutes les données sont
stockées et chiffrées sur l'appareil.

Dans le build 6 (version 1.1.0), l'utilisateur peut supprimer définitivement son
compte directement dans l'app : Réglages → Compte → « Supprimer mon compte ».
Après confirmation, cela supprime définitivement le profil, toutes les données
locales, le mot de passe maître et les sauvegardes chiffrées du dossier cloud
lié, puis revient à l'écran d'accueil. Aucun email ni contact support n'est
nécessaire.

Une vidéo de tout le parcours est jointe dans les notes de l'App Review. Merci.
```

---

## 4. CHECKLIST DE RE-SOUMISSION (App Store Connect)

- [ ] Build **6** sélectionné dans la version 1.1.0 (retirer le build 5, ajouter le 6).
- [ ] Vidéo jointe dans **Notes de l'App Review**.
- [ ] Texte des Notes collé (section 2).
- [ ] Réponse au reviewer postée dans le **Centre de résolution** (section 3).
- [ ] Clic sur **« Mettre à jour la vérification »** pour re-soumettre.
```
