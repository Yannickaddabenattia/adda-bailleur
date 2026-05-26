import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/hover_card.dart';
import '../../models/credit_immobilier.dart';
import '../../services/credit_service.dart';
import '../../services/logement_service.dart';
import 'credit_detail_screen.dart';
import 'credit_form_screen.dart';

class CreditListScreen extends StatefulWidget {
  final String? logementId;
  const CreditListScreen({super.key, this.logementId});

  @override
  State<CreditListScreen> createState() => _CreditListScreenState();
}

class _CreditListScreenState extends State<CreditListScreen> {
  StatutCredit? _filtreStatut;

  @override
  Widget build(BuildContext context) {
    final all = context.watch<CreditService>().all;
    var items = widget.logementId == null
        ? all
        : all.where((c) => c.logementId == widget.logementId).toList();
    if (_filtreStatut != null) {
      items = items.where((c) => c.statut == _filtreStatut).toList();
    }

    final compteurs = <StatutCredit, int>{
      for (final s in StatutCredit.values)
        s: all.where((c) =>
                widget.logementId == null || c.logementId == widget.logementId)
            .where((c) => c.statut == s)
            .length,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Crédits immobiliers')),
      body: Column(
        children: [
          if (all.isNotEmpty) _StatutFilterBar(
            current: _filtreStatut,
            counts: compteurs,
            onChanged: (s) => setState(() => _filtreStatut = s),
          ),
          Expanded(
            child: items.isEmpty
                ? _Empty(onAdd: () => _addNew(context))
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _CreditCard(credit: items[i]),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addNew(context),
        icon: const Icon(Icons.add),
        label: const Text('Nouveau'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
    );
  }

  void _addNew(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CreditFormScreen(initialLogementId: widget.logementId),
    ));
  }
}

class _StatutFilterBar extends StatelessWidget {
  final StatutCredit? current;
  final Map<StatutCredit, int> counts;
  final ValueChanged<StatutCredit?> onChanged;
  const _StatutFilterBar({
    required this.current,
    required this.counts,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _Chip(
              label: 'Tous',
              count: total,
              selected: current == null,
              onTap: () => onChanged(null),
            ),
            const SizedBox(width: 8),
            _Chip(
              label: 'Actifs',
              count: counts[StatutCredit.actif] ?? 0,
              color: const Color(0xFF059669),
              selected: current == StatutCredit.actif,
              onTap: () => onChanged(StatutCredit.actif),
            ),
            const SizedBox(width: 8),
            _Chip(
              label: 'Rachetés',
              count: counts[StatutCredit.rachete] ?? 0,
              color: const Color(0xFF7C3AED),
              selected: current == StatutCredit.rachete,
              onTap: () => onChanged(StatutCredit.rachete),
            ),
            const SizedBox(width: 8),
            _Chip(
              label: 'Clôturés',
              count: counts[StatutCredit.cloture] ?? 0,
              color: const Color(0xFF6E7280),
              selected: current == StatutCredit.cloture,
              onTap: () => onChanged(StatutCredit.cloture),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final int count;
  final Color? color;
  final bool selected;
  final VoidCallback onTap;
  const _Chip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final base = color ?? AppColors.primary;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? base : base.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? base : base.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : base,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: selected
                    ? Colors.white.withValues(alpha: 0.25)
                    : base.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : base,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreditCard extends StatelessWidget {
  final CreditImmobilier credit;
  const _CreditCard({required this.credit});

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(locale: 'fr_FR', symbol: '€');
    final logement =
        context.watch<LogementService>().byId(credit.logementId);
    final moisEcoules = credit.moisEcoulesA(DateTime.now());
    final progress = credit.dureeMois == 0
        ? 0.0
        : moisEcoules / credit.dureeMois;
    return HoverCard(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CreditDetailScreen(creditId: credit.id),
      )),
      accent: AppColors.primary,
      borderRadius: BorderRadius.circular(16),
      padding: const EdgeInsets.all(14),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.account_balance_outlined,
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
                              credit.libelle,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          StatutBadge(statut: credit.statut),
                        ],
                      ),
                      Text(
                        logement?.libelle ?? '?',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${money.format(credit.mensualiteTotale)}/mois',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: AppColors.divider,
            ),
            const SizedBox(height: 4),
            Text(
              '$moisEcoules / ${credit.dureeMois} mois — CRD ${money.format(credit.capitalRestantA(DateTime.now()))}',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
    );
  }
}

/// Badge de statut, réutilisable.
class StatutBadge extends StatelessWidget {
  final StatutCredit statut;
  const StatutBadge({super.key, required this.statut});

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (statut) {
      StatutCredit.actif => ('Actif', const Color(0xFF059669), Icons.bolt_outlined),
      StatutCredit.rachete => ('Racheté', const Color(0xFF7C3AED), Icons.swap_horiz_outlined),
      StatutCredit.cloture => ('Clôturé', const Color(0xFF6E7280), Icons.check_circle_outline),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 0.6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: color,
            ),
          ),
        ],
      ),
    );
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
            Icon(Icons.account_balance_outlined,
                size: 72,
                color: AppColors.textSecondary.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            const Text('Aucun crédit',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text(
              'Suivez le remboursement de vos crédits immobiliers '
              'avec décomposition capital / intérêts.',
              style: TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Nouveau crédit'),
            ),
          ],
        ),
      ),
    );
  }
}
