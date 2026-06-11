import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/country.dart';

/// Section « Pays & localisation fiscale » du formulaire de bien.
///
/// Affichée uniquement quand le feature flag `AppConstants.multiPaysActif` est
/// actif. Composant **contrôlé** : l'état (pays/région/canton + valeurs) est
/// porté par le formulaire parent ; ce widget ne fait qu'afficher et notifier.
class CountrySection extends StatelessWidget {
  final Country country;
  final BeRegion? beRegion;
  final ChCanton? chCanton;

  // Champs Belgique
  final TextEditingController revenuCadastral;
  final TextEditingController precompteImmo;

  // Champs Suisse
  final TextEditingController valeurFiscale;
  final TextEditingController tauxFoncierPourMille;
  final TextEditingController tauxReferenceContrat;

  final ValueChanged<Country> onCountry;
  final ValueChanged<BeRegion?> onRegion;
  final ValueChanged<ChCanton?> onCanton;

  const CountrySection({
    super.key,
    required this.country,
    required this.beRegion,
    required this.chCanton,
    required this.revenuCadastral,
    required this.precompteImmo,
    required this.valeurFiscale,
    required this.tauxFoncierPourMille,
    required this.tauxReferenceContrat,
    required this.onCountry,
    required this.onRegion,
    required this.onCanton,
  });

  static const _numFmt = <TextInputFormatter>[];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<Country>(
          initialValue: country,
          decoration: const InputDecoration(
            labelText: 'Pays du bien *',
            prefixIcon: Icon(Icons.public),
          ),
          items: [
            for (final c in Country.values)
              DropdownMenuItem(
                value: c,
                child: Text('${c.flag}  ${c.label}'),
              ),
          ],
          onChanged: (v) => onCountry(v ?? Country.france),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 8),
          child: Text(
            'Devise : ${country.defaultCurrency}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),

        // ── Belgique ──────────────────────────────────────────────────────
        if (country == Country.belgique) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<BeRegion>(
            initialValue: beRegion,
            decoration: const InputDecoration(
              labelText: 'Région *',
              prefixIcon: Icon(Icons.map_outlined),
            ),
            items: [
              for (final r in BeRegion.values)
                DropdownMenuItem(value: r, child: Text(r.label)),
            ],
            onChanged: onRegion,
          ),
          const SizedBox(height: 12),
          _numField(
            controller: revenuCadastral,
            label: 'Revenu cadastral (RC 1975, non indexé)',
            hint: 'Sur l’avertissement-extrait de rôle',
            icon: Icons.account_balance_outlined,
          ),
          const SizedBox(height: 12),
          _numField(
            controller: precompteImmo,
            label: 'Précompte immobilier annuel (optionnel)',
            hint: 'Montant payé / estimé',
            icon: Icons.receipt_long_outlined,
          ),
        ],

        // ── Suisse ────────────────────────────────────────────────────────
        if (country == Country.suisse) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<ChCanton>(
            initialValue: chCanton,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Canton *',
              prefixIcon: Icon(Icons.map_outlined),
            ),
            items: [
              for (final c in ChCanton.values)
                DropdownMenuItem(value: c, child: Text(c.label)),
            ],
            onChanged: onCanton,
          ),
          const SizedBox(height: 12),
          _numField(
            controller: valeurFiscale,
            label: 'Valeur fiscale du bien (CHF)',
            hint: 'Impôt foncier / fortune',
            icon: Icons.account_balance_outlined,
          ),
          const SizedBox(height: 12),
          _numField(
            controller: tauxFoncierPourMille,
            label: 'Taux d’impôt foncier (‰)',
            hint: '0 si le canton n’en prélève pas',
            icon: Icons.percent_outlined,
          ),
          const SizedBox(height: 12),
          _numField(
            controller: tauxReferenceContrat,
            label: 'Taux de référence à la signature (%)',
            hint: 'Ex : 1,50',
            icon: Icons.trending_up_outlined,
          ),
        ],
      ],
    );
  }

  Widget _numField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: _numFmt,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
      ),
    );
  }
}
