import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/credit_immobilier.dart';
import '../../models/depense.dart';
import '../../models/logement.dart';
import '../../services/credit_service.dart';
import '../../services/depense_service.dart';
import '../../services/logement_service.dart';

/// Détails de la KPI « Dépenses + crédits » : pour chaque logement, la
/// répartition par catégorie (assurance prêt, assurance PNO, taxe foncière,
/// réparations, entretien, charges, honoraires, autre) avec le détail ligne
/// à ligne.
class SortiesDetailScreen extends StatelessWidget {
  final int year;
  final String? logementId;

  /// Surplus d'impôt sur le revenu dû aux revenus fonciers de N-1
  /// (impôt avec foncier − impôt sans foncier).
  final double surplusIRFoncier;

  /// Prélèvements sociaux (CSG + CRDS + solidarité) sur revenu foncier + LMNP de N-1.
  /// Taux variables : foncier 17,2 % (LFSS 2026 inchangé), meublé 18,6 % dès 2025.
  final double prelevementsSociaux;

  const SortiesDetailScreen({
    super.key,
    required this.year,
    this.logementId,
    this.surplusIRFoncier = 0,
    this.prelevementsSociaux = 0,
  });

  static const List<String> _moisCourts = [
    'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
    'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.',
  ];

  // Ordre d'affichage des catégories de dépenses.
  static const List<String> _ordreCategories = [
    ExpenseCategories.taxeFonciere,
    ExpenseCategories.assurance,
    ExpenseCategories.reparations,
    ExpenseCategories.entretien,
    ExpenseCategories.charges,
    ExpenseCategories.honoraires,
    ExpenseCategories.autre,
  ];

  @override
  Widget build(BuildContext context) {
    final logements = context.watch<LogementService>().all;
    final depensesSvc = context.watch<DepenseService>();
    final creditsSvc = context.watch<CreditService>();
    final money = NumberFormat.currency(locale: 'fr_FR', symbol: '€');

    final filteredLogements = logementId == null
        ? logements
        : logements.where((l) => l.id == logementId).toList();

    final blocs = <_LogementBloc>[];
    var totalGeneral = 0.0;
    var totalCapitalInterets = 0.0;
    var totalAssurancePret = 0.0;
    var totalDepenses = 0.0;

    for (final l in filteredLogements) {
      // Crédits du logement
      final credits = creditsSvc.forLogement(l.id);
      final creditLines = <_CreditDetail>[];
      var capInt = 0.0;
      var assPret = 0.0;
      for (final c in credits) {
        var cCapInt = 0.0;
        var cAssPret = 0.0;
        for (var m = 1; m <= 12; m++) {
          final date = DateTime(year, m, 1);
          if (date.isBefore(DateTime(c.dateDebut.year, c.dateDebut.month, 1))) {
            continue;
          }
          if (date.isAfter(c.dateFin)) continue;
          final mens = c.mensualiteTotaleA(date);
          final assMois = c.assuranceMensuelle;
          cAssPret += assMois;
          cCapInt += (mens - assMois);
        }
        if (cCapInt > 0 || cAssPret > 0) {
          creditLines.add(_CreditDetail(
            credit: c,
            capitalInterets: cCapInt,
            assurance: cAssPret,
          ));
          capInt += cCapInt;
          assPret += cAssPret;
        }
      }

      // Dépenses par catégorie
      final depenses =
          depensesSvc.forLogement(l.id).where((d) => d.date.year == year).toList();
      depenses.sort((a, b) => b.date.compareTo(a.date));
      final parCategorie = <String, List<Depense>>{};
      for (final d in depenses) {
        parCategorie.putIfAbsent(d.categorie, () => []).add(d);
      }
      var depensesTotal = 0.0;
      for (final d in depenses) {
        depensesTotal += d.montant;
      }

      final total = capInt + assPret + depensesTotal;
      if (total == 0) continue;

      blocs.add(_LogementBloc(
        logement: l,
        credits: creditLines,
        capitalInterets: capInt,
        assurancePret: assPret,
        depensesParCategorie: parCategorie,
        depensesTotal: depensesTotal,
        total: total,
      ));
      totalGeneral += total;
      totalCapitalInterets += capInt;
      totalAssurancePret += assPret;
      totalDepenses += depensesTotal;
    }

    blocs.sort((a, b) => b.total.compareTo(a.total));

    final impotFoncier = surplusIRFoncier + prelevementsSociaux;
    final totalAvecImpot = totalGeneral + impotFoncier;

    return Scaffold(
      backgroundColor: context.backgroundColor,
      appBar: AppBar(
        title: const Text('Dépenses + crédits'),
      ),
      body: totalAvecImpot == 0
          ? _EmptyState(year: year)
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                _TotalCard(
                  total: totalAvecImpot,
                  capitalInterets: totalCapitalInterets,
                  assurancePret: totalAssurancePret,
                  depenses: totalDepenses,
                  impotFoncier: impotFoncier,
                  year: year,
                  money: money,
                ),
                const SizedBox(height: 20),
                if (impotFoncier > 0) ...[
                  _ImpotFoncierCard(
                    surplusIR: surplusIRFoncier,
                    prelevementsSociaux: prelevementsSociaux,
                    anneeRevenus: year - 1,
                    money: money,
                  ),
                  const SizedBox(height: 16),
                ],
                ...blocs.map((b) => Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _LogementCard(
                        bloc: b,
                        money: money,
                        moisCourts: _moisCourts,
                        ordreCategories: _ordreCategories,
                      ),
                    )),
              ],
            ),
    );
  }
}

class _ImpotFoncierCard extends StatelessWidget {
  final double surplusIR;
  final double prelevementsSociaux;
  final int anneeRevenus;
  final NumberFormat money;
  const _ImpotFoncierCard({
    required this.surplusIR,
    required this.prelevementsSociaux,
    required this.anneeRevenus,
    required this.money,
  });

  @override
  Widget build(BuildContext context) {
    final total = surplusIR + prelevementsSociaux;
    return Container(
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: const Color(0xFF7C3AED).withValues(alpha: 0.08),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(15)),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color:
                        const Color(0xFF7C3AED).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.calculate_outlined,
                      color: Color(0xFF7C3AED), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Impôts fonciers',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: context.textPrimaryColor,
                        ),
                      ),
                      Text(
                        'sur revenus locatifs $anneeRevenus',
                        style: TextStyle(
                          fontSize: 11,
                          color: context.textSecondaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  money.format(total),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF7C3AED),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Column(
              children: [
                _ImpotLine(
                  icon: Icons.trending_up_rounded,
                  label: 'Surplus IR',
                  detail: 'impôt avec foncier − impôt sans foncier',
                  value: surplusIR,
                  money: money,
                ),
                _ImpotLine(
                  icon: Icons.percent_rounded,
                  label: 'Prélèvements sociaux',
                  detail: 'CSG + CRDS · 17,2 % à 18,6 %',
                  value: prelevementsSociaux,
                  money: money,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ImpotLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final String detail;
  final double value;
  final NumberFormat money;
  const _ImpotLine({
    required this.icon,
    required this.label,
    required this.detail,
    required this.value,
    required this.money,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: context.textSecondaryColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimaryColor,
                  ),
                ),
                Text(
                  detail,
                  style: TextStyle(
                    fontSize: 11,
                    color: context.textSecondaryColor,
                  ),
                ),
              ],
            ),
          ),
          Text(
            money.format(value),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: context.textPrimaryColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _LogementBloc {
  final Logement logement;
  final List<_CreditDetail> credits;
  final double capitalInterets;
  final double assurancePret;
  final Map<String, List<Depense>> depensesParCategorie;
  final double depensesTotal;
  final double total;
  const _LogementBloc({
    required this.logement,
    required this.credits,
    required this.capitalInterets,
    required this.assurancePret,
    required this.depensesParCategorie,
    required this.depensesTotal,
    required this.total,
  });
}

class _CreditDetail {
  final CreditImmobilier credit;
  final double capitalInterets;
  final double assurance;
  const _CreditDetail({
    required this.credit,
    required this.capitalInterets,
    required this.assurance,
  });
}

class _TotalCard extends StatelessWidget {
  final double total;
  final double capitalInterets;
  final double assurancePret;
  final double depenses;
  final double impotFoncier;
  final int year;
  final NumberFormat money;
  const _TotalCard({
    required this.total,
    required this.capitalInterets,
    required this.assurancePret,
    required this.depenses,
    required this.impotFoncier,
    required this.year,
    required this.money,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.trending_down_rounded,
                    color: AppColors.accent, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total sorties en $year',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: context.textSecondaryColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      money.format(total),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppColors.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _LineRow(label: 'Capital + intérêts', value: capitalInterets, money: money),
          _LineRow(label: 'Assurance prêt', value: assurancePret, money: money),
          _LineRow(label: 'Dépenses', value: depenses, money: money),
          _LineRow(
            label: 'Impôts fonciers (N-1)',
            value: impotFoncier,
            money: money,
            last: true,
          ),
        ],
      ),
    );
  }
}

class _LineRow extends StatelessWidget {
  final String label;
  final double value;
  final NumberFormat money;
  final bool last;
  const _LineRow({
    required this.label,
    required this.value,
    required this.money,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: 6, bottom: last ? 0 : 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: context.textSecondaryColor,
              ),
            ),
          ),
          Text(
            money.format(value),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: context.textPrimaryColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _LogementCard extends StatelessWidget {
  final _LogementBloc bloc;
  final NumberFormat money;
  final List<String> moisCourts;
  final List<String> ordreCategories;
  const _LogementCard({
    required this.bloc,
    required this.money,
    required this.moisCourts,
    required this.ordreCategories,
  });

  @override
  Widget build(BuildContext context) {
    final sections = <Widget>[];

    if (bloc.capitalInterets > 0) {
      sections.add(_CategorySection(
        icon: Icons.account_balance_rounded,
        title: 'Capital + intérêts',
        total: bloc.capitalInterets,
        money: money,
        children: bloc.credits
            .where((c) => c.capitalInterets > 0)
            .map((c) => _SimpleLine(
                  label: c.credit.libelle.isNotEmpty
                      ? c.credit.libelle
                      : 'Crédit immobilier',
                  detail: 'capital + intérêts annuels',
                  value: c.capitalInterets,
                  money: money,
                ))
            .toList(),
      ));
    }

    if (bloc.assurancePret > 0) {
      sections.add(_CategorySection(
        icon: Icons.security_rounded,
        title: 'Assurance prêt',
        total: bloc.assurancePret,
        money: money,
        children: bloc.credits
            .where((c) => c.assurance > 0)
            .map((c) => _SimpleLine(
                  label: c.credit.libelle.isNotEmpty
                      ? c.credit.libelle
                      : 'Crédit immobilier',
                  detail:
                      '${money.format(c.credit.assuranceMensuelle)}/mois',
                  value: c.assurance,
                  money: money,
                ))
            .toList(),
      ));
    }

    // Catégories de dépenses dans l'ordre défini, puis les éventuelles
    // catégories custom à la fin.
    final cats = bloc.depensesParCategorie.keys.toList();
    final ordered = <String>[
      ...ordreCategories.where(cats.contains),
      ...cats.where((c) => !ordreCategories.contains(c)),
    ];
    for (final cat in ordered) {
      final items = bloc.depensesParCategorie[cat]!;
      final totalCat = items.fold<double>(0, (s, d) => s + d.montant);
      sections.add(_CategorySection(
        icon: _iconForCategory(cat),
        title: cat,
        total: totalCat,
        money: money,
        children: items
            .map((d) => _SimpleLine(
                  label: d.libelle.isNotEmpty ? d.libelle : cat,
                  detail:
                      '${d.date.day} ${moisCourts[d.date.month - 1]} $cat'
                      .toLowerCase(),
                  value: d.montant,
                  money: money,
                ))
            .toList(),
      ));
    }

    return Container(
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.06),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(15),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.home_work_rounded,
                      color: AppColors.accent, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    bloc.logement.libelle,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: context.textPrimaryColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  money.format(bloc.total),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.accent,
                  ),
                ),
              ],
            ),
          ),
          ...sections,
        ],
      ),
    );
  }

  static IconData _iconForCategory(String cat) {
    switch (cat) {
      case ExpenseCategories.taxeFonciere:
        return Icons.account_balance_outlined;
      case ExpenseCategories.assurance:
        return Icons.shield_outlined;
      case ExpenseCategories.reparations:
        return Icons.build_outlined;
      case ExpenseCategories.entretien:
        return Icons.cleaning_services_outlined;
      case ExpenseCategories.charges:
        return Icons.receipt_outlined;
      case ExpenseCategories.honoraires:
        return Icons.gavel_rounded;
      default:
        return Icons.label_outline;
    }
  }
}

class _CategorySection extends StatelessWidget {
  final IconData icon;
  final String title;
  final double total;
  final NumberFormat money;
  final List<Widget> children;
  const _CategorySection({
    required this.icon,
    required this.title,
    required this.total,
    required this.money,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
            child: Row(
              children: [
                Icon(icon, size: 18, color: context.textSecondaryColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: context.textPrimaryColor,
                    ),
                  ),
                ),
                Text(
                  money.format(total),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimaryColor,
                  ),
                ),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _SimpleLine extends StatelessWidget {
  final String label;
  final String detail;
  final double value;
  final NumberFormat money;
  const _SimpleLine({
    required this.label,
    required this.detail,
    required this.value,
    required this.money,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 4,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: context.textSecondaryColor,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    color: context.textPrimaryColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  detail,
                  style: TextStyle(
                    fontSize: 11,
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
            money.format(value),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: context.textPrimaryColor,
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
            Icon(
              Icons.inbox_outlined,
              size: 64,
              color: context.textSecondaryColor,
            ),
            const SizedBox(height: 14),
            Text(
              'Aucune sortie en $year',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: context.textPrimaryColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Aucune dépense ni mensualité de crédit n\'a été enregistrée.',
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
