import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/logement.dart';
import '../../../models/revision_loyer.dart';
import '../../../services/logement_service.dart';
import '../../../services/revision_loyer_service.dart';
import 'revision_loyer_form_screen.dart';

class RevisionsLoyerScreen extends StatelessWidget {
  final String logementId;
  const RevisionsLoyerScreen({super.key, required this.logementId});

  @override
  Widget build(BuildContext context) {
    final logement = context.watch<LogementService>().byId(logementId);
    if (logement == null) {
      return const Scaffold(
        body: Center(child: Text('Logement introuvable')),
      );
    }
    final revisions = context
        .watch<RevisionLoyerService>()
        .forLogement(logementId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Révisions de loyer'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _BaseCard(logement: logement),
          const SizedBox(height: 16),
          if (revisions.isEmpty)
            _Empty(
              onAdd: () => _addNew(context, logement),
            )
          else
            ...revisions.map(
              (r) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _RevisionCard(revision: r),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addNew(context, logement),
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
    );
  }

  void _addNew(BuildContext context, Logement l) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RevisionLoyerFormScreen(logement: l),
    ));
  }
}

class _BaseCard extends StatelessWidget {
  final Logement logement;
  const _BaseCard({required this.logement});

  @override
  Widget build(BuildContext context) {
    final money =
        NumberFormat.currency(locale: 'fr_FR', symbol: '€', decimalDigits: 2);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.home_work_outlined,
                color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Loyer initial du logement',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${money.format(logement.loyerHC)} HC '
                  '+ ${money.format(logement.charges)} charges',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Utilisé tant qu\'aucune révision n\'est applicable.',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RevisionCard extends StatelessWidget {
  final RevisionLoyer revision;
  const _RevisionCard({required this.revision});

  @override
  Widget build(BuildContext context) {
    final money =
        NumberFormat.currency(locale: 'fr_FR', symbol: '€', decimalDigits: 2);
    final dfMonth = DateFormat('MMMM yyyy', 'fr_FR');
    final dateLabel = dfMonth.format(revision.dateEffet);
    final logement =
        context.read<LogementService>().byId(revision.logementId);
    final isFuture = revision.dateEffet.isAfter(DateTime.now());

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        if (logement == null) return;
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => RevisionLoyerFormScreen(
            logement: logement,
            existing: revision,
          ),
        ));
      },
      onLongPress: () => _confirmDelete(context),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.history_outlined,
                      color: AppColors.primary, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'À partir de '
                        '${dateLabel[0].toUpperCase()}${dateLabel.substring(1)}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${money.format(revision.loyerHC)} HC '
                        '+ ${money.format(revision.charges)} charges '
                        '= ${money.format(revision.total)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isFuture)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'À venir',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
              ],
            ),
            if (revision.motif.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                revision.motif,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer la révision ?'),
        content: const Text(
          'Les quittances déjà créées ne seront pas modifiées. Seules les '
          'futures quittances seront affectées.',
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
    if (ok == true && context.mounted) {
      await context.read<RevisionLoyerService>().delete(revision.id);
    }
  }
}

class _Empty extends StatelessWidget {
  final VoidCallback onAdd;
  const _Empty({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      child: Column(
        children: [
          Icon(Icons.history_outlined,
              size: 56,
              color: AppColors.textSecondary.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          const Text('Aucune révision',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 6),
          const Text(
            'Ajoutez une révision pour suivre les changements de loyer dans le '
            'temps. Les nouvelles quittances utiliseront le bon montant '
            'selon la période choisie.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Nouvelle révision'),
          ),
        ],
      ),
    );
  }
}
