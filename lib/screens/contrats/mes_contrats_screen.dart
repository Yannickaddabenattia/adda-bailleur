import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/contrat_bail.dart';
import '../../services/contrat_bail_service.dart';
import '../../services/locataire_service.dart';
import '../../services/logement_service.dart';
import 'contrat_bail_detail_screen.dart';
import 'contrat_bail_list_screen.dart';

/// Vue agrégée de tous les contrats de bail, tous logements confondus.
/// Accessible depuis l'écran d'accueil. Tap sur un contrat → détail.
/// Pour créer un nouveau bail, l'utilisateur passe par la fiche d'un logement.
class MesContratsScreen extends StatelessWidget {
  const MesContratsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final contrats = context.watch<ContratBailService>().all;
    final logementSvc = context.watch<LogementService>();
    final locataireSvc = context.watch<LocataireService>();
    final df = DateFormat('dd/MM/yyyy', 'fr_FR');
    final money = NumberFormat.currency(locale: 'fr_FR', symbol: '€');

    return Scaffold(
      appBar: AppBar(title: const Text('Mes contrats de bail')),
      body: contrats.isEmpty
          ? const _Empty()
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: contrats.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (ctx, i) {
                final c = contrats[i];
                final logement = logementSvc.byId(c.logementId);
                final locNames = c.locataireIds
                    .map((id) => locataireSvc.byId(id)?.fullName)
                    .whereType<String>()
                    .join(', ');
                return _ContratTile(
                  contrat: c,
                  logementLabel: logement?.libelle ?? 'Logement supprimé',
                  locatairesLabel:
                      locNames.isEmpty ? 'Aucun locataire' : locNames,
                  dateFmt: df,
                  money: money,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          ContratBailDetailScreen(bailId: c.id),
                    ),
                  ),
                  onOpenLogement: logement == null
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ContratBailListScreen(
                                  logement: logement),
                            ),
                          ),
                );
              },
            ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

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
              'Ouvre la fiche d\'un logement pour créer ton premier bail '
              '(vide, meublé, colocation, saisonnier ou mobilité). '
              'Le PDF est conforme loi ALUR.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContratTile extends StatelessWidget {
  final ContratBail contrat;
  final String logementLabel;
  final String locatairesLabel;
  final DateFormat dateFmt;
  final NumberFormat money;
  final VoidCallback onTap;
  final VoidCallback? onOpenLogement;

  const _ContratTile({
    required this.contrat,
    required this.logementLabel,
    required this.locatairesLabel,
    required this.dateFmt,
    required this.money,
    required this.onTap,
    required this.onOpenLogement,
  });

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(contrat.statut);
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
                Expanded(
                  child: Text(
                    contrat.reference,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    contrat.statut.label,
                    style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              contrat.type.label,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.home_outlined,
                    size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    logementLabel,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.people_alt_outlined,
                    size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    locatairesLabel,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '${dateFmt.format(contrat.dateDebut)} → ${dateFmt.format(contrat.dateFin)}',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
                const Spacer(),
                Text(
                  money.format(contrat.loyerHC + contrat.charges),
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ],
            ),
            if (onOpenLogement != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onOpenLogement,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Nouveau bail pour ce logement'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
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
        return AppColors.primary;
      case BailStatus.enCours:
        return AppColors.success;
      case BailStatus.termine:
        return AppColors.textSecondary;
      case BailStatus.resilie:
        return AppColors.error;
    }
  }
}
