import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../services/tenant_share_service.dart';

class ReceivedBundleDetailScreen extends StatelessWidget {
  final String bundleId;
  const ReceivedBundleDetailScreen({super.key, required this.bundleId});

  @override
  Widget build(BuildContext context) {
    final bundle = context.watch<TenantShareService>().bundleById(bundleId);
    if (bundle == null) {
      return const Scaffold(
        body: Center(child: Text('Document introuvable.')),
      );
    }
    final content = context.read<TenantShareService>().decodeBundle(bundle);
    final df = DateFormat('dd/MM/yyyy', 'fr_FR');
    final money = NumberFormat.currency(locale: 'fr_FR', symbol: '€');

    return Scaffold(
      appBar: AppBar(
        title: Text('De ${content.fromName}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(context, bundleId),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _Card(
            title: 'Origine',
            children: [
              _Row(label: 'Propriétaire', value: content.fromName),
              _Row(label: 'Email', value: content.fromEmail),
              _Row(
                label: 'Partagé le',
                value: df.format(content.sharedAt.toLocal()),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (content.logements.isNotEmpty) _buildLogementsCard(content),
          if (content.etatDesLieux.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildEdlCard(content, df),
          ],
          if (content.quittances.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildQuittancesCard(content, df, money),
          ],
        ],
      ),
    );
  }

  Widget _buildLogementsCard(ReceivedShareContent c) {
    return _Card(
      title: 'Logement(s)',
      children: c.logements.map((l) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l['libelle'] as String,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                '${l['adresse']}, ${l['codePostal']} ${l['ville']}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildEdlCard(ReceivedShareContent c, DateFormat df) {
    return _Card(
      title: 'États des lieux',
      children: c.etatDesLieux.map((e) {
        final date = DateTime.parse(e['date'] as String);
        final pieces = e['pieces'] as List;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    e['type'] == 'entree'
                        ? Icons.login_rounded
                        : Icons.logout_rounded,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'EDL ${e['type']} — ${df.format(date)}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${pieces.length} pièce(s) · ${e['status']}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              if (e['integrityHash'] != null) ...[
                const SizedBox(height: 2),
                Text(
                  'Hash : ${e['integrityHash']}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildQuittancesCard(
    ReceivedShareContent c,
    DateFormat df,
    NumberFormat money,
  ) {
    const mois = [
      'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
      'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
    ];
    return _Card(
      title: 'Quittances',
      children: c.quittances.map((q) {
        final month = q['periodMonth'] as int;
        final year = q['periodYear'] as int;
        final total =
            (q['loyerHC'] as num).toDouble() + (q['charges'] as num).toDouble();
        final dp = DateTime.parse(q['datePaiement'] as String);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${mois[month - 1][0].toUpperCase()}${mois[month - 1].substring(1)} $year',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      'Payée le ${df.format(dp)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                money.format(total),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  void _confirmDelete(BuildContext context, String id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ce document reçu ?'),
        content: const Text(
          'Le document sera retiré de votre appareil. Vous pourrez le '
          'réimporter si vous avez toujours le fichier et le code.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: () async {
              await context.read<TenantShareService>().deleteBundle(id);
              if (!ctx.mounted) return;
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Card({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
          Text(value, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }
}
