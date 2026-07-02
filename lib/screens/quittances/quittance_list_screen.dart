import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/hover_card.dart';
import '../../models/quittance.dart';
import '../../services/locataire_service.dart';
import '../../services/logement_service.dart';
import '../../services/quittance_service.dart';
import 'quittance_detail_screen.dart';
import 'quittance_form_screen.dart';

class QuittanceListScreen extends StatelessWidget {
  const QuittanceListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final items = context.watch<QuittanceService>().all;

    return Scaffold(
      appBar: AppBar(title: const Text('Quittances de loyer')),
      body: items.isEmpty
          ? _EmptyState(onAdd: () => _startNew(context))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (ctx, i) => _QuittanceCard(quittance: items[i]),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _startNew(context),
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
    );
  }

  void _startNew(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const QuittanceFormScreen()),
    );
  }
}

class _QuittanceCard extends StatelessWidget {
  final Quittance quittance;
  const _QuittanceCard({required this.quittance});

  @override
  Widget build(BuildContext context) {
    final logement =
        context.watch<LogementService>().byId(quittance.logementId);
    final locataire =
        context.watch<LocataireService>().byId(quittance.locataireId);
    final money = NumberFormat.currency(locale: 'fr_FR', symbol: '€');

    return HoverCard(
      accent: AppColors.primary,
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              QuittanceDetailScreen(quittanceId: quittance.id),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.receipt_long_outlined,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          quittance.periodLabel[0].toUpperCase() +
                              quittance.periodLabel.substring(1),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (quittance.isPaiementPartiel) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.warningSoft,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Reçu partiel',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppColors.warning,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${logement?.libelle ?? '(logement supprimé)'} — ${locataire?.fullName ?? '(locataire supprimé)'}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (quittance.isPaiementPartiel)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    money.format(quittance.montantPayePeriode),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.warning,
                    ),
                  ),
                  Text(
                    '/ ${money.format(quittance.total)}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              )
            else
              Text(
                money.format(quittance.total),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_outlined,
                size: 72,
                color: AppColors.textSecondary.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            const Text(
              'Aucune quittance',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Créez une quittance de loyer conforme loi ALUR.',
              style: TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Nouvelle quittance'),
            ),
          ],
        ),
      ),
    );
  }
}
