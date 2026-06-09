import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/logement.dart';
import '../../services/credit_service.dart';
import '../../services/depense_service.dart';
import '../../services/logement_service.dart';
import '../../services/quittance_service.dart';

/// Bilan depuis l'acquisition pour un logement donné.
///
/// Agrège sur toute la période :
/// - Recettes : toutes les quittances émises (loyer HC + charges)
/// - Dépenses : toutes les dépenses enregistrées
/// - Crédits : somme des mensualités payées année par année
/// - Bilan net = recettes − dépenses − crédits
///
/// Période = de [Logement.dateAcquisition] jusqu'à aujourd'hui (ou à défaut,
/// de la première quittance jusqu'à aujourd'hui).
class BilanLogementScreen extends StatelessWidget {
  final String logementId;
  const BilanLogementScreen({super.key, required this.logementId});

  @override
  Widget build(BuildContext context) {
    final logement = context.watch<LogementService>().byId(logementId);
    if (logement == null) {
      return const Scaffold(
        body: Center(child: Text('Logement introuvable.')),
      );
    }
    final quittancesSvc = context.watch<QuittanceService>();
    final depensesSvc = context.watch<DepenseService>();
    final creditsSvc = context.watch<CreditService>();

    final money = NumberFormat.currency(locale: 'fr_FR', symbol: '€');
    final money0 = NumberFormat.currency(
        locale: 'fr_FR', symbol: '€', decimalDigits: 0);

    final now = DateTime.now();
    final quittances = quittancesSvc.forLogement(logementId);
    final depenses = depensesSvc.forLogement(logementId);
    final credits = creditsSvc.forLogement(logementId);

    // Période couverte : dateAcquisition si renseignée, sinon plus ancienne
    // quittance / dépense / crédit.
    DateTime debut = logement.dateAcquisition ?? now;
    for (final q in quittances) {
      final d = DateTime(q.periodYear, q.periodMonth, 1);
      if (d.isBefore(debut)) debut = d;
    }
    for (final d in depenses) {
      if (d.date.isBefore(debut)) debut = d.date;
    }
    for (final c in credits) {
      if (c.dateDebut.isBefore(debut)) debut = c.dateDebut;
    }
    final anneeDebut = debut.year;
    final anneeFin = now.year;
    final dureeAnnees = anneeFin - anneeDebut + 1;

    // Agrégations sur la période.
    final recettes =
        quittances.fold<double>(0, (s, q) => s + q.total);
    final totalDepenses =
        depenses.fold<double>(0, (s, d) => s + d.montant);
    var totalCredits = 0.0;
    for (var y = anneeDebut; y <= anneeFin; y++) {
      totalCredits += creditsSvc.annualPaymentsForLogement(logementId, y);
    }
    final sorties = totalDepenses + totalCredits;
    final bilan = recettes - sorties;
    final rentabiliteBrute = logement.prixRevient > 0 && dureeAnnees > 0
        ? (recettes / dureeAnnees) / logement.prixRevient * 100
        : 0.0;

    // Recettes/dépenses/crédits par année pour le tableau.
    final lignesAnnee = <_LigneAnnee>[];
    for (var y = anneeDebut; y <= anneeFin; y++) {
      final r = quittances
          .where((q) => q.periodYear == y)
          .fold<double>(0, (s, q) => s + q.total);
      final d = depenses
          .where((dp) => dp.date.year == y)
          .fold<double>(0, (s, dp) => s + dp.montant);
      final c = creditsSvc.annualPaymentsForLogement(logementId, y);
      lignesAnnee.add(_LigneAnnee(
        annee: y,
        recettes: r,
        depenses: d,
        credits: c,
        bilan: r - d - c,
      ));
    }
    lignesAnnee.sort((a, b) => b.annee.compareTo(a.annee));

    return Scaffold(
      backgroundColor: context.backgroundColor,
      appBar: AppBar(
        title: const Text('Bilan depuis acquisition'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _HeaderCard(
            logement: logement,
            anneeDebut: anneeDebut,
            anneeFin: anneeFin,
            dureeAnnees: dureeAnnees,
          ),
          const SizedBox(height: 16),
          _BilanCard(
            bilan: bilan,
            recettes: recettes,
            sorties: sorties,
            money: money,
          ),
          const SizedBox(height: 16),
          _KpiGrid(
            recettes: recettes,
            depenses: totalDepenses,
            credits: totalCredits,
            rentabiliteBrute: rentabiliteBrute,
            money: money0,
          ),
          if (logement.prixRevient > 0) ...[
            const SizedBox(height: 16),
            _PrixRevientCard(
              prixRevient: logement.prixRevient,
              bilan: bilan,
              money: money,
            ),
          ],
          const SizedBox(height: 20),
          _SectionHeader(
            title: 'Détail par année',
            count: lignesAnnee.length,
          ),
          const SizedBox(height: 8),
          ...lignesAnnee.map((l) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _LigneAnneeTile(ligne: l, money: money0),
              )),
        ],
      ),
    );
  }
}

class _LigneAnnee {
  final int annee;
  final double recettes;
  final double depenses;
  final double credits;
  final double bilan;
  const _LigneAnnee({
    required this.annee,
    required this.recettes,
    required this.depenses,
    required this.credits,
    required this.bilan,
  });
}

class _HeaderCard extends StatelessWidget {
  final Logement logement;
  final int anneeDebut;
  final int anneeFin;
  final int dureeAnnees;
  const _HeaderCard({
    required this.logement,
    required this.anneeDebut,
    required this.anneeFin,
    required this.dureeAnnees,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.home_work_rounded,
                color: AppColors.primary, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  logement.libelle,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: context.textPrimaryColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Période : $anneeDebut → $anneeFin '
                  '($dureeAnnees an${dureeAnnees > 1 ? 's' : ''})',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.textSecondaryColor,
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

class _BilanCard extends StatelessWidget {
  final double bilan;
  final double recettes;
  final double sorties;
  final NumberFormat money;
  const _BilanCard({
    required this.bilan,
    required this.recettes,
    required this.sorties,
    required this.money,
  });

  @override
  Widget build(BuildContext context) {
    final positif = bilan >= 0;
    final couleur = positif ? AppColors.success : AppColors.error;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: couleur.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Bilan net cumulé',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: context.textSecondaryColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            money.format(bilan),
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: couleur,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.arrow_upward_rounded,
                  size: 14, color: AppColors.success),
              const SizedBox(width: 4),
              Text(
                'Encaissé : ${money.format(recettes)}',
                style: TextStyle(
                  fontSize: 12,
                  color: context.textPrimaryColor,
                ),
              ),
              const SizedBox(width: 12),
              Icon(Icons.arrow_downward_rounded,
                  size: 14, color: AppColors.error),
              const SizedBox(width: 4),
              Text(
                'Sortie : ${money.format(sorties)}',
                style: TextStyle(
                  fontSize: 12,
                  color: context.textPrimaryColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  final double recettes;
  final double depenses;
  final double credits;
  final double rentabiliteBrute;
  final NumberFormat money;
  const _KpiGrid({
    required this.recettes,
    required this.depenses,
    required this.credits,
    required this.rentabiliteBrute,
    required this.money,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _KpiTile(
                icon: Icons.trending_up_rounded,
                color: AppColors.success,
                label: 'Loyers encaissés',
                value: money.format(recettes),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _KpiTile(
                icon: Icons.receipt_long_rounded,
                color: AppColors.accent,
                label: 'Dépenses',
                value: money.format(depenses),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _KpiTile(
                icon: Icons.account_balance_rounded,
                color: AppColors.accent,
                label: 'Crédits payés',
                value: money.format(credits),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _KpiTile(
                icon: Icons.percent_rounded,
                color: AppColors.primary,
                label: 'Rentabilité brute',
                value: rentabiliteBrute > 0
                    ? '${rentabiliteBrute.toStringAsFixed(2)} %'
                    : '—',
                detail: rentabiliteBrute > 0
                    ? 'loyers/an ÷ prix de revient'
                    : 'prix de revient manquant',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _KpiTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String? detail;
  const _KpiTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: context.textSecondaryColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: context.textPrimaryColor,
            ),
          ),
          if (detail != null) ...[
            const SizedBox(height: 2),
            Text(
              detail!,
              style: TextStyle(
                fontSize: 10,
                color: context.textSecondaryColor,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

class _PrixRevientCard extends StatelessWidget {
  final double prixRevient;
  final double bilan;
  final NumberFormat money;
  const _PrixRevientCard({
    required this.prixRevient,
    required this.bilan,
    required this.money,
  });

  @override
  Widget build(BuildContext context) {
    final pctAmorti = prixRevient > 0
        ? (bilan / prixRevient * 100).clamp(0.0, 100.0)
        : 0.0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.savings_outlined,
                  color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'Prix de revient',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: context.textPrimaryColor,
                ),
              ),
              const Spacer(),
              Text(
                money.format(prixRevient),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: context.textPrimaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: pctAmorti / 100,
              minHeight: 8,
              backgroundColor: context.dividerColor,
              valueColor: const AlwaysStoppedAnimation(AppColors.success),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            bilan >= 0
                ? 'Le bilan net couvre ${pctAmorti.toStringAsFixed(1)} % du prix de revient.'
                : 'Bilan net négatif — pas encore d\'amortissement.',
            style: TextStyle(
              fontSize: 11,
              color: context.textSecondaryColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  const _SectionHeader({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: context.textPrimaryColor,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: context.dividerColor.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: context.textSecondaryColor,
            ),
          ),
        ),
      ],
    );
  }
}

class _LigneAnneeTile extends StatelessWidget {
  final _LigneAnnee ligne;
  final NumberFormat money;
  const _LigneAnneeTile({required this.ligne, required this.money});

  @override
  Widget build(BuildContext context) {
    final positif = ligne.bilan >= 0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${ligne.annee}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: context.textPrimaryColor,
                ),
              ),
              const Spacer(),
              Text(
                money.format(ligne.bilan),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: positif ? AppColors.success : AppColors.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _MiniStat(
                label: 'Loyers',
                value: money.format(ligne.recettes),
                color: AppColors.success,
              ),
              const SizedBox(width: 14),
              _MiniStat(
                label: 'Dépenses',
                value: money.format(ligne.depenses),
                color: AppColors.accent,
              ),
              const SizedBox(width: 14),
              _MiniStat(
                label: 'Crédits',
                value: money.format(ligne.credits),
                color: AppColors.accent,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: context.textSecondaryColor,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}
