# adda_location

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Multi-pays (Belgique / Suisse)

Le support Belgique + Suisse (fiscalité, devises, baux/EDL/quittances, validations)
est implémenté **derrière un feature flag désactivé par défaut** :

```dart
// lib/core/constants.dart
static const bool multiPaysActif = false;
```

Tant que le flag est `false`, l'application est **strictement identique** à la version
France : sélecteur de pays masqué, tous les biens en France/EUR, aucun template ni
validation BE/CH atteignable. Les données existantes sont préservées (champs Hive neufs,
nullable, défaut France — voir `test/legacy_logement_migration_test.dart`).

### Procédure de réactivation

1. **Validation juridique/fiscale** (obligatoire avant tout build destiné aux stores) :
   - faire valider par **un juriste belge** les templates `lib/core/templates/countries/belgium_documents.dart`
     et les valeurs fiscales de `lib/services/fiscalite/countries/belgium.dart` ;
   - faire valider par **une régie / fiduciaire suisse** `switzerland_documents.dart` et `switzerland.dart`.
2. **Compléter les `⚠️`** : remplacer chaque placeholder `[À VALIDER JURISTE — …]`
   par le texte validé, et renseigner les valeurs codées `null` dans les maps fiscales
   (coefficients RC belges, paliers du taux de référence suisse, etc.). Sources de
   référence : `~/Downloads/FISCALITE-BELGIQUE-2006-2026.md`, `~/Downloads/FISCALITE-SUISSE-2006-2026.md`.
3. **QA manuelle** : créer un bien 🇧🇪 et un bien 🇨🇭, vérifier le parcours
   (création, estimation fiscale, bilans multi-devises, écran « points à valider »).
4. **Activer le flag** : passer `multiPaysActif = true`.
5. **Tests** : `flutter test` doit rester 100 % vert
   (`legacy_logement_migration_test`, `be_/ch_fiscal_test`, `be_/ch_lease_template_test`,
   `deposit_validation_by_country_test`, `indexation_rule_by_country_test`,
   `document_generation_guard_test`, `hive_schema_safety_test`).
6. **Bilans globaux** : vérifier que les montants restent groupés par devise
   (jamais de somme EUR + CHF — voir `CurrencyFormat.formatByCurrency`).

> Les documents BE/CH générés portent le pied de page « Modèle indicatif — faire valider
> par un professionnel local avant premier usage » tant que la validation n'est pas faite.
