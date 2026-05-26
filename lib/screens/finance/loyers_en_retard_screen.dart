import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/hover_card.dart';
import '../../models/locataire.dart';
import '../../models/logement.dart';
import '../../services/locataire_service.dart';
import '../../services/logement_service.dart';
import '../../services/quittance_service.dart';
import '../../services/revision_loyer_service.dart';
import '../quittances/quittance_form_screen.dart';

/// Liste les loyers non encaissés : pour chaque (logement, locataire, mois)
/// de l'année courante où aucune quittance n'a été émise.
class LoyersEnRetardScreen extends StatelessWidget {
  final int year;
  final String? logementId;

  const LoyersEnRetardScreen({
    super.key,
    required this.year,
    this.logementId,
  });

  static const List<String> _mois = [
    'Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin',
    'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre',
  ];

  @override
  Widget build(BuildContext context) {
    final logements = context.watch<LogementService>().all;
    final locataires = context.watch<LocataireService>().all;
    final quittances = context.watch<QuittanceService>().all;
    final revisionsSvc = context.watch<RevisionLoyerService>();
    final money = NumberFormat.currency(locale: 'fr_FR', symbol: '€');

    final filtered = logementId == null
        ? logements
        : logements.where((l) => l.id == logementId).toList();

    final now = DateTime.now();
    final maxMonth =
        year < now.year ? 12 : (year == now.year ? now.month : 0);

    final retards = <_Retard>[];
    var totalDu = 0.0;

    for (final l in filtered) {
      final occupants =
          locataires.where((loc) => loc.logementIds.contains(l.id)).toList();
      for (var m = 1; m <= maxMonth; m++) {
        final monthDate = DateTime(year, m, 1);
        final daysInMonth = DateTime(year, m + 1, 0).day;
        var occupiedDays = 0;
        final activeOnAnyDay = <Locataire>{};
        for (var d = 1; d <= daysInMonth; d++) {
          final day = DateTime(year, m, d);
          var dayActive = false;
          for (final loc in occupants) {
            final de = loc.dateEntree;
            if (de != null &&
                day.isBefore(DateTime(de.year, de.month, de.day))) {
              continue;
            }
            final ds = loc.dateSortie;
            if (ds != null &&
                day.isAfter(DateTime(ds.year, ds.month, ds.day))) {
              continue;
            }
            dayActive = true;
            activeOnAnyDay.add(loc);
          }
          if (dayActive) occupiedDays++;
        }
        if (occupiedDays == 0) continue;
        final exists = quittances.any((q) =>
            q.logementId == l.id &&
            q.periodYear == year &&
            q.periodMonth == m);
        if (exists) continue;
        final eff = revisionsSvc.loyerEffectifAt(
          logement: l,
          date: monthDate,
        );
        final du = eff.total * occupiedDays / daysInMonth;
        final actifs = activeOnAnyDay.toList();
        final principal = actifs.firstWhere(
          (loc) => loc.isPrincipal,
          orElse: () => actifs.first,
        );
        retards.add(_Retard(
          logement: l,
          locataire: principal,
          month: m,
          montantDu: du,
        ));
        totalDu += du;
      }
    }

    retards.sort((a, b) {
      final byLogement = a.logement.libelle.compareTo(b.logement.libelle);
      if (byLogement != 0) return byLogement;
      return a.month.compareTo(b.month);
    });

    return Scaffold(
      backgroundColor: context.backgroundColor,
      appBar: AppBar(
        title: const Text('Loyers en retard'),
      ),
      body: retards.isEmpty
          ? _EmptyState(year: year)
          : Column(
              children: [
                _Summary(
                  count: retards.length,
                  total: totalDu,
                  year: year,
                  money: money,
                ),
                Expanded(
                  child: ListView.separated(
                    padding:
                        const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: retards.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _RetardTile(
                      retard: retards[i],
                      year: year,
                      money: money,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _Retard {
  final Logement logement;
  final Locataire locataire;
  final int month;
  final double montantDu;
  const _Retard({
    required this.logement,
    required this.locataire,
    required this.month,
    required this.montantDu,
  });
}

class _Summary extends StatelessWidget {
  final int count;
  final double total;
  final int year;
  final NumberFormat money;
  const _Summary({
    required this.count,
    required this.total,
    required this.year,
    required this.money,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.error.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.error_outline_rounded,
                color: AppColors.error, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$count loyer${count > 1 ? 's' : ''} non encaissé${count > 1 ? 's' : ''} en $year',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimaryColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Total dû : ${money.format(total)}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.error,
                    fontWeight: FontWeight.w600,
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

class _RetardTile extends StatelessWidget {
  final _Retard retard;
  final int year;
  final NumberFormat money;
  const _RetardTile({
    required this.retard,
    required this.year,
    required this.money,
  });

  @override
  Widget build(BuildContext context) {
    final mois = LoyersEnRetardScreen._mois[retard.month - 1];
    return HoverCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => QuittanceFormScreen(
            initialLogementId: retard.logement.id,
            initialLocataireId: retard.locataire.id,
            initialPeriode: DateTime(year, retard.month),
          ),
        ),
      ),
      accent: AppColors.error,
      borderRadius: BorderRadius.circular(14),
      padding: const EdgeInsets.all(14),
      child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.schedule_rounded,
                  color: AppColors.error, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$mois $year',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: context.textPrimaryColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${retard.locataire.firstName} ${retard.locataire.lastName} · ${retard.logement.libelle}',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.textSecondaryColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              money.format(retard.montantDu),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.error,
              ),
            ),
          ],
        ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final int year;
  const _EmptyState({required this.year});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.check_circle_outline_rounded,
              size: 64,
              color: AppColors.success,
            ),
            const SizedBox(height: 14),
            Text(
              'Aucun loyer en retard en $year',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: context.textPrimaryColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Toutes les quittances attendues ont été émises.',
              style: TextStyle(
                fontSize: 13,
                color: context.textSecondaryColor,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
