import 'package:flutter/material.dart';

import '../../core/currency_format.dart';
import '../../core/storage/local_database.dart';
import '../../models/country.dart';
import '../../models/fiscal_settings.dart';
import '../../models/logement.dart';
import '../../services/fiscalite/countries/registry.dart';
import '../../services/fiscalite/country_tax_config.dart';

/// Écran d'**estimation fiscale par bien** pour la Belgique et la Suisse.
///
/// La France n'est jamais routée ici (sa fiscalité reste au niveau du foyer,
/// écran dédié). Affiche un bandeau « estimation », le détail du calcul, et —
/// si des données ⚠️ manquent — la liste à compléter **sans jamais afficher de
/// montant calculé sur une valeur manquante**.
class ForeignFiscaliteScreen extends StatelessWidget {
  final Logement logement;
  final int year;

  const ForeignFiscaliteScreen({
    super.key,
    required this.logement,
    required this.year,
  });

  @override
  Widget build(BuildContext context) {
    final config = countryConfigFor(logement.country);
    final settings =
        LocalDatabase.fiscalSettingsBox.get(FiscalSettings.key) ??
            FiscalSettings();
    final TaxEstimate? est = config.computeRentalTax(
      logement: logement,
      year: year,
      settings: settings,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('Fiscalité ${logement.country.flag} · $year'),
      ),
      body: est == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'La fiscalité française est calculée au niveau du foyer '
                  '(voir l’écran Fiscalité général).',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _EstimateBanner(country: logement.country),
                const SizedBox(height: 16),
                if (est.missingInputs.isNotEmpty)
                  _MissingInputsCard(missing: est.missingInputs),
                if (est.missingInputs.isNotEmpty) const SizedBox(height: 16),
                _ResultCard(estimate: est),
                const SizedBox(height: 16),
                _RulesCard(
                  deposit: config.depositRule(
                    logement: logement,
                    leaseDate: DateTime(year, 1, 1),
                  ),
                  indexation: config.indexationInfo(logement: logement),
                ),
              ],
            ),
    );
  }
}

class _EstimateBanner extends StatelessWidget {
  final Country country;
  const _EstimateBanner({required this.country});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade700),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Colors.amber.shade800),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Estimation indicative — à valider avec votre '
              '${country == Country.suisse ? 'fiduciaire' : 'expert-comptable'}. '
              'Renvoi au simulateur de l’administration ${country.label}.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _MissingInputsCard extends StatelessWidget {
  final List<String> missing;
  const _MissingInputsCard({required this.missing});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.edit_note),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'À compléter pour calculer le montant',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final m in missing)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text('•  $m'),
              ),
            const SizedBox(height: 8),
            Text(
              'Tant que ces valeurs ne sont pas saisies, aucun montant n’est '
              'calculé (pas d’estimation sur une donnée manquante).',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final TaxEstimate estimate;
  const _ResultCard({required this.estimate});

  @override
  Widget build(BuildContext context) {
    final cur = estimate.currencyCode;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Détail du calcul',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            for (final line in estimate.lines) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Text(line.label)),
                  const SizedBox(width: 12),
                  Text(
                    line.amount == null
                        ? '—'
                        : CurrencyFormat.format(line.amount!, cur),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              if (line.note != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(line.note!,
                      style: Theme.of(context).textTheme.bodySmall),
                ),
              const SizedBox(height: 4),
            ],
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Impôt estimé',
                    style: Theme.of(context).textTheme.titleMedium),
                Text(
                  estimate.estimatedTax == null
                      ? 'à compléter'
                      : CurrencyFormat.format(estimate.estimatedTax!, cur),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RulesCard extends StatelessWidget {
  final DepositRule deposit;
  final RentIndexationInfo indexation;
  const _RulesCard({required this.deposit, required this.indexation});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Règles locales',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.savings_outlined),
              title: const Text('Garantie locative'),
              subtitle: Text(
                '${deposit.maxMonthsRent == null ? 'à confirmer' : '${deposit.maxMonthsRent} mois max'}'
                '${deposit.blockedAccountRequired ? ' · compte bloqué' : ''}'
                '${deposit.note.isEmpty ? '' : '\n${deposit.note}'}',
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.trending_up),
              title: Text('Indexation : ${indexation.indexName}'),
              subtitle: Text(indexation.description),
            ),
          ],
        ),
      ),
    );
  }
}
