import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/contrat_bail.dart';
import '../../models/logement.dart';
import '../../services/contrat_bail_service.dart';
import 'contrat_bail_form_screen.dart';
import 'contrat_bail_detail_screen.dart';

/// Liste des contrats de bail d'un logement. Permet d'en créer un nouveau,
/// d'éditer, de générer le PDF, ou de visualiser.
class ContratBailListScreen extends StatelessWidget {
  final Logement logement;
  const ContratBailListScreen({super.key, required this.logement});

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<ContratBailService>();
    final contrats = svc.forLogement(logement.id);
    final df = DateFormat('dd MMM yyyy', 'fr_FR');
    final money = NumberFormat.currency(locale: 'fr_FR', symbol: '€');

    return Scaffold(
      appBar: AppBar(
        title: Text('Bails — ${logement.libelle}'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openNew(context),
        icon: const Icon(Icons.add),
        label: const Text('Nouveau bail'),
      ),
      body: contrats.isEmpty
          ? _Empty(onCreate: () => _openNew(context))
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
              itemCount: contrats.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (ctx, i) {
                final c = contrats[i];
                return _ContratCard(
                  contrat: c,
                  dateFmt: df,
                  money: money,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ContratBailDetailScreen(bailId: c.id),
                    ),
                  ),
                );
              },
            ),
    );
  }

  void _openNew(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ContratBailFormScreen(logement: logement),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final VoidCallback onCreate;
  const _Empty({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.description_outlined,
                size: 64, color: context.dividerColor),
            const SizedBox(height: 16),
            const Text(
              'Aucun contrat de bail',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Crée ton premier bail pour ce logement. Choisis le type '
              '(vide, meublé, colocation, saisonnier, mobilité), saisis les '
              'parties, le loyer, et génère un PDF conforme loi ALUR.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text('Créer un bail'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContratCard extends StatelessWidget {
  final ContratBail contrat;
  final DateFormat dateFmt;
  final NumberFormat money;
  final VoidCallback onTap;
  const _ContratCard({
    required this.contrat,
    required this.dateFmt,
    required this.money,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(contrat.statut);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.surfaceColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    contrat.type.label,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    contrat.statut.label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  contrat.reference,
                  style: TextStyle(
                      fontSize: 11, color: context.textSecondaryColor),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Du ${dateFmt.format(contrat.dateDebut)} au '
              '${dateFmt.format(contrat.dateFin)}',
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              '${money.format(contrat.loyerHC)} HC '
              '+ ${money.format(contrat.charges)} charges '
              '= ${money.format(contrat.totalMensuel)}/mois',
              style: TextStyle(
                  fontSize: 13, color: context.textSecondaryColor),
            ),
            if (contrat.estColocation) ...[
              const SizedBox(height: 4),
              Text(
                '${contrat.locataireIds.length} colocataires',
                style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.accent,
                    fontWeight: FontWeight.w700),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _statusColor(BailStatus s) {
    switch (s) {
      case BailStatus.brouillon:
        return AppColors.textSecondary;
      case BailStatus.signe:
      case BailStatus.enCours:
        return AppColors.success;
      case BailStatus.termine:
        return AppColors.textSecondary;
      case BailStatus.resilie:
        return AppColors.error;
    }
  }
}
