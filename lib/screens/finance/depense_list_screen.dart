import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/hover_card.dart';
import '../../models/depense.dart';
import '../../services/depense_service.dart';
import '../../services/logement_service.dart';
import 'depense_form_screen.dart';

class DepenseListScreen extends StatelessWidget {
  final String? logementId;
  const DepenseListScreen({super.key, this.logementId});

  @override
  Widget build(BuildContext context) {
    final all = context.watch<DepenseService>().all;
    final items = logementId == null
        ? all
        : all.where((d) => d.logementId == logementId).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dépenses'),
      ),
      body: items.isEmpty
          ? _Empty(onAdd: () => _addNew(context))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _DepenseCard(depense: items[i]),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addNew(context),
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
    );
  }

  void _addNew(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DepenseFormScreen(initialLogementId: logementId),
    ));
  }
}

class _DepenseCard extends StatelessWidget {
  final Depense depense;
  const _DepenseCard({required this.depense});

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(locale: 'fr_FR', symbol: '€');
    final df = DateFormat('dd/MM/yyyy', 'fr_FR');
    final logement =
        context.watch<LogementService>().byId(depense.logementId);

    return GestureDetector(
      onLongPress: () => _confirmDelete(context),
      child: HoverCard(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => DepenseFormScreen(existing: depense),
        )),
        accent: AppColors.error,
        borderRadius: BorderRadius.circular(16),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.trending_down_rounded,
                color: AppColors.error,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    depense.libelle,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${depense.categorie} • ${logement?.libelle ?? '?'} • ${df.format(depense.date)}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (depense.justificatifs.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.attach_file,
                            size: 13,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${depense.justificatifs.length} justif.',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              money.format(depense.montant),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.error,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer la dépense ?'),
        content: Text(
          '${depense.libelle}\nCette action est irréversible.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirm == true && context.mounted) {
      await context.read<DepenseService>().delete(depense.id);
    }
  }
}

class _Empty extends StatelessWidget {
  final VoidCallback onAdd;
  const _Empty({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.trending_down_rounded,
                size: 72,
                color: AppColors.textSecondary.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            const Text('Aucune dépense',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text(
              'Ajoutez vos charges, taxes, réparations ou autres dépenses.',
              style: TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Nouvelle dépense'),
            ),
          ],
        ),
      ),
    );
  }
}
