import 'package:flutter/material.dart';

import '../../core/templates/countries/belgium_documents.dart';
import '../../core/templates/countries/country_document_template.dart';
import '../../core/templates/countries/switzerland_documents.dart';
import '../../models/country.dart';

/// Écran récapitulatif des points `[À VALIDER JURISTE]` (A.2).
///
/// Liste, par document (bail / EDL / quittance), tous les placeholders à faire
/// valider par un professionnel local avant usage. Les documents BE/CH ne sont
/// que des **modèles indicatifs** ([kModeleIndicatifFooter]).
class PlaceholdersRecapScreen extends StatelessWidget {
  final Country country;

  const PlaceholdersRecapScreen({super.key, required this.country});

  Map<String, CountryDocumentTemplate> get _docs => switch (country) {
        Country.belgique => BelgiumDocuments.all,
        Country.suisse => SwitzerlandDocuments.all,
        Country.france => const {},
      };

  @override
  Widget build(BuildContext context) {
    final docs = _docs;
    final total = docs.values.expand((d) => d.placeholders).length;

    return Scaffold(
      appBar: AppBar(
        title: Text('À valider — ${country.flag} ${country.label}'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.shade700),
            ),
            child: Text(
              '$total point(s) à faire valider par un juriste local avant '
              'premier usage. $kModeleIndicatifFooter',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 16),
          for (final entry in docs.entries) ...[
            Text(
              _docLabel(entry.key),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            if (entry.value.placeholders.isEmpty)
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 12),
                child: Text('Aucun point à valider.'),
              )
            else
              ...entry.value.placeholders.map(
                (p) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.gavel_outlined),
                    title: Text(p),
                    dense: true,
                  ),
                ),
              ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  static String _docLabel(String docType) => switch (docType) {
        'bail' => 'Bail',
        'edl' => 'État des lieux',
        'quittance' => 'Quittance',
        _ => docType,
      };
}
