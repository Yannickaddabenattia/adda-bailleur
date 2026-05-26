import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/hover_card.dart';
import '../../models/credit_immobilier.dart';
import '../../services/credit_service.dart';
import '../../services/logement_service.dart';
import 'credit_amortization_screen.dart';
import 'credit_form_screen.dart';
import 'credit_list_screen.dart' show StatutBadge;
import 'rachat_form_screen.dart';

const _kPurple = Color(0xFF6366F1);
const _kPurpleDark = Color(0xFF4F46E5);
const _kPurpleLight = Color(0xFF8B5CF6);
const _kBlue = Color(0xFF3B82F6);
const _kPink = Color(0xFFEC4899);
const _kOrange = Color(0xFFF59E0B);
const _kGreen = Color(0xFF10B981);

class CreditDetailScreen extends StatelessWidget {
  final String creditId;
  const CreditDetailScreen({super.key, required this.creditId});

  @override
  Widget build(BuildContext context) {
    final credit = context.watch<CreditService>().byId(creditId);
    if (credit == null) {
      return const Scaffold(body: Center(child: Text('Crédit introuvable')));
    }
    final logement =
        context.watch<LogementService>().byId(credit.logementId);
    final money = NumberFormat.currency(
      locale: 'fr_FR',
      symbol: '€',
      decimalDigits: 0,
    );
    final money2 = NumberFormat.currency(locale: 'fr_FR', symbol: '€');
    final dfMonth = DateFormat('MMM yyyy', 'fr_FR');

    final now = DateTime.now();
    final crd = credit.capitalRestantA(now);
    final moisEcoules = credit.moisEcoulesA(now);
    final dureeRef = _dureeReference(credit);
    final progress = dureeRef == 0 ? 0.0 : (moisEcoules / dureeRef).clamp(0.0, 1.0);
    final dateFin = credit.dateFin;
    final pctRembourse = credit.capitalEmprunte == 0
        ? 0.0
        : (1 - crd / credit.capitalEmprunte).clamp(0.0, 1.0);

    final totalCout = credit.capitalEmprunte +
        credit.totalInterets +
        credit.totalAssurance;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        title: Column(
          children: const [
            Text(
              'DÉTAIL',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
            SizedBox(height: 1),
            Text(
              'Crédit immobilier',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CreditFormScreen(existing: credit),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
            onPressed: () => _confirmDelete(context, credit),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          _HeroCard(
            credit: credit,
            logement: logement?.libelle ?? '',
            money: money2,
            pctRembourse: pctRembourse,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  label: 'CAPITAL',
                  value: money.format(credit.capitalEmprunte),
                  icon: Icons.account_balance_wallet_outlined,
                  color: _kBlue,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatCard(
                  label: 'TAUX',
                  value: _formatTaux(credit.tauxAnnuel),
                  suffix: '%',
                  icon: Icons.percent_rounded,
                  color: _kPurpleLight,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatCard(
                  label: 'DURÉE',
                  value: '${(credit.dureeMois / 12).round()}',
                  suffix: 'ans',
                  icon: Icons.calendar_month_outlined,
                  color: _kOrange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _ProgressCard(
            progress: progress,
            moisEcoules: moisEcoules,
            dureeMois: dureeRef,
            dateDebut: credit.dateDebut,
            dateFin: dateFin,
            dfMonth: dfMonth,
          ),
          const SizedBox(height: 14),
          _RepartitionCard(
            crd: crd,
            interets: credit.totalInterets,
            assurance: credit.totalAssurance,
            total: totalCout,
            money: money,
          ),
          if (credit.isRachete) ...[
            const SizedBox(height: 14),
            _RachatBlock(credit: credit, money: money2, dfMonth: dfMonth),
          ],
          if (credit.notes.isNotEmpty) ...[
            const SizedBox(height: 14),
            _NotesCard(notes: credit.notes),
          ],
          const SizedBox(height: 16),
          _QuickActions(credit: credit),
          const SizedBox(height: 14),
          _AmortissementButton(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CreditAmortizationScreen(credit: credit),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatTaux(double t) {
    return t.toStringAsFixed(2).replaceAll('.', ',');
  }

  static int _dureeReference(CreditImmobilier c) {
    if (c.isRachete && c.dateRachat != null) {
      final pre = c.moisEcoulesA(c.dateRachat!);
      final post =
          (c.nouvelleDureeMois ?? math.max(0, c.dureeMois - pre));
      return pre + post;
    }
    return c.dureeMois;
  }

  Future<void> _confirmDelete(
      BuildContext context, CreditImmobilier credit) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer le crédit ?'),
        content: const Text('Cette action est irréversible.'),
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
      await context.read<CreditService>().delete(credit.id);
      if (context.mounted) Navigator.of(context).pop();
    }
  }
}

// ---------------------------------------------------------------------------
//  HERO CARD (purple gradient + circular progress)
// ---------------------------------------------------------------------------

class _HeroCard extends StatelessWidget {
  final CreditImmobilier credit;
  final String logement;
  final NumberFormat money;
  final double pctRembourse;
  const _HeroCard({
    required this.credit,
    required this.logement,
    required this.money,
    required this.pctRembourse,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          height: 200,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_kPurpleDark, _kPurple, _kPurpleLight],
            ),
            boxShadow: [
              BoxShadow(
                color: _kPurple.withValues(alpha: 0.35),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
        ),
        Positioned(
          right: -30,
          top: -20,
          child: _Bubble(size: 140, color: Colors.white.withValues(alpha: 0.10)),
        ),
        Positioned(
          right: 60,
          bottom: -30,
          child: _Bubble(size: 90, color: Colors.white.withValues(alpha: 0.08)),
        ),
        Positioned(
          right: 130,
          top: 30,
          child: _Bubble(size: 50, color: Colors.white.withValues(alpha: 0.10)),
        ),
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.account_balance_outlined,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'CRÉDIT PRINCIPAL',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    letterSpacing: 1.4,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xCCFFFFFF),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  credit.libelle.isNotEmpty
                                      ? credit.libelle
                                      : (logement.isEmpty ? '—' : logement),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      const Text(
                        'MENSUALITÉ',
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 1.4,
                          fontWeight: FontWeight.w700,
                          color: Color(0xCCFFFFFF),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _formatMontant(credit.mensualiteTotale),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              height: 1,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Padding(
                            padding: EdgeInsets.only(bottom: 4),
                            child: Text(
                              '€/mois',
                              style: TextStyle(
                                color: Color(0xCCFFFFFF),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.shield_outlined,
                                color: Colors.white, size: 12),
                            const SizedBox(width: 4),
                            Text(
                              'assurance ${money.format(credit.assuranceMensuelle)}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    StatutBadge(statut: credit.statut),
                    const Spacer(),
                    _CircularProgress(value: pctRembourse),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _formatMontant(double m) {
    final fmt = NumberFormat('#,##0.00', 'fr_FR');
    return fmt.format(m);
  }
}

class _Bubble extends StatelessWidget {
  final double size;
  final Color color;
  const _Bubble({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

class _CircularProgress extends StatelessWidget {
  final double value;
  const _CircularProgress({required this.value});

  @override
  Widget build(BuildContext context) {
    final pct = (value * 100).round();
    return SizedBox(
      width: 78,
      height: 78,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 78,
            height: 78,
            child: CircularProgressIndicator(
              value: 1,
              strokeWidth: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.18),
              valueColor: AlwaysStoppedAnimation(
                Colors.white.withValues(alpha: 0.18),
              ),
            ),
          ),
          SizedBox(
            width: 78,
            height: 78,
            child: CircularProgressIndicator(
              value: value == 0 ? 0.001 : value,
              strokeWidth: 6,
              backgroundColor: Colors.transparent,
              valueColor: const AlwaysStoppedAnimation(_kGreen),
              strokeCap: StrokeCap.round,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$pct %',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
              const SizedBox(height: 1),
              const Text(
                'REMBOURSÉ',
                style: TextStyle(
                  color: Color(0xCCFFFFFF),
                  fontSize: 7.5,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  STAT CARD
// ---------------------------------------------------------------------------

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String? suffix;
  final IconData icon;
  final Color color;
  const _StatCard({
    required this.label,
    required this.value,
    this.suffix,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 9.5,
                    letterSpacing: 1.0,
                    fontWeight: FontWeight.w700,
                    color: color.withValues(alpha: 0.85),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'serif',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    height: 1,
                  ),
                ),
              ),
              if (suffix != null) ...[
                const SizedBox(width: 3),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    suffix!,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  PROGRESS CARD (Avancement)
// ---------------------------------------------------------------------------

class _ProgressCard extends StatelessWidget {
  final double progress;
  final int moisEcoules;
  final int dureeMois;
  final DateTime dateDebut;
  final DateTime dateFin;
  final DateFormat dfMonth;
  const _ProgressCard({
    required this.progress,
    required this.moisEcoules,
    required this.dureeMois,
    required this.dateDebut,
    required this.dateFin,
    required this.dfMonth,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: _kGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.trending_up_rounded,
                  size: 18,
                  color: _kGreen,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Avancement',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _kGreen.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '$moisEcoules / $dureeMois mois',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _kGreen,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(builder: (ctx, c) {
            final w = c.maxWidth;
            final pos = (w * progress).clamp(8.0, w - 8);
            return SizedBox(
              height: 14,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  Container(
                    height: 6,
                    width: pos,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_kGreen, Color(0xFF34D399)],
                      ),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  Positioned(
                    left: pos - 7,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: _kGreen, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: _kGreen.withValues(alpha: 0.3),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 10),
          Row(
            children: [
              _PointLabel(
                icon: Icons.flag_outlined,
                text: dfMonth.format(dateDebut),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _kGreen.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: const Text(
                  "aujourd'hui",
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: _kGreen,
                  ),
                ),
              ),
              const Spacer(),
              _PointLabel(
                icon: Icons.flag_rounded,
                text: dfMonth.format(dateFin),
                rightAlign: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PointLabel extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool rightAlign;
  const _PointLabel({
    required this.icon,
    required this.text,
    this.rightAlign = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!rightAlign) Icon(icon, size: 11, color: AppColors.textSecondary),
        if (!rightAlign) const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (rightAlign) const SizedBox(width: 4),
        if (rightAlign) Icon(icon, size: 11, color: AppColors.textSecondary),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
//  REPARTITION CARD
// ---------------------------------------------------------------------------

class _RepartitionCard extends StatelessWidget {
  final double crd;
  final double interets;
  final double assurance;
  final double total;
  final NumberFormat money;
  const _RepartitionCard({
    required this.crd,
    required this.interets,
    required this.assurance,
    required this.total,
    required this.money,
  });

  @override
  Widget build(BuildContext context) {
    final t = total <= 0 ? 1.0 : total;
    final pCrd = (crd / t).clamp(0.0, 1.0);
    final pInt = (interets / t).clamp(0.0, 1.0);
    final pAss = (assurance / t).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.donut_small_rounded,
                  size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              const Text(
                'Répartition du coût',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                'Total : ${money.format(total)}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  Expanded(
                    flex: (pCrd * 1000).round(),
                    child: Container(color: _kPurple),
                  ),
                  Expanded(
                    flex: (pInt * 1000).round(),
                    child: Container(color: _kPink),
                  ),
                  Expanded(
                    flex: (pAss * 1000).round(),
                    child: Container(color: _kOrange),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  label: 'RESTANT',
                  value: money.format(crd),
                  color: _kPurple,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MiniStat(
                  label: 'INTÉRÊTS',
                  value: money.format(interets),
                  color: _kPink,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MiniStat(
                  label: 'ASSURANCE',
                  value: money.format(assurance),
                  color: _kOrange,
                ),
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
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 9,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                    color: color.withValues(alpha: 0.85),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'serif',
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  QUICK ACTIONS
// ---------------------------------------------------------------------------

class _QuickActions extends StatelessWidget {
  final CreditImmobilier credit;
  const _QuickActions({required this.credit});

  Future<void> _markCloture(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Marquer comme clôturé ?'),
        content: const Text(
          'Le crédit sera considéré soldé. Les mensualités futures '
          'ne seront plus comptées dans les totaux.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    credit.statut = StatutCredit.cloture;
    credit.dateCloture = DateTime.now();
    await context.read<CreditService>().update(credit);
  }

  Future<void> _annulerCloture(BuildContext context) async {
    credit.statut = credit.dateRachat != null
        ? StatutCredit.rachete
        : StatutCredit.actif;
    credit.dateCloture = null;
    await context.read<CreditService>().update(credit);
  }

  @override
  Widget build(BuildContext context) {
    if (credit.isCloture) {
      return _ActionTile(
        icon: Icons.replay_outlined,
        color: _kGreen,
        title: 'Annuler la clôture',
        subtitle: 'Le crédit redevient actif',
        onTap: () => _annulerCloture(context),
      );
    }

    final left = credit.isRachete
        ? _ActionTile(
            icon: Icons.edit_outlined,
            color: _kPurpleLight,
            title: 'Modifier le rachat',
            subtitle: 'Conditions du refi',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => RachatFormScreen(credit: credit),
            )),
          )
        : _ActionTile(
            icon: Icons.swap_horiz_outlined,
            color: _kPurpleLight,
            title: 'Ajouter un rachat',
            subtitle: 'Refinancer ce prêt',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => RachatFormScreen(credit: credit),
            )),
          );

    final right = _ActionTile(
      icon: Icons.check_circle_outline,
      color: _kGreen,
      title: 'Marquer clôturé',
      subtitle: 'Crédit soldé',
      onTap: () => _markCloture(context),
    );

    return Row(
      children: [
        Expanded(child: left),
        const SizedBox(width: 10),
        Expanded(child: right),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _ActionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return HoverCard(
      onTap: onTap,
      accent: color,
      borderRadius: BorderRadius.circular(14),
      borderColor: color.withValues(alpha: 0.30),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  AMORTISSEMENT BUTTON
// ---------------------------------------------------------------------------

class _AmortissementButton extends StatefulWidget {
  final VoidCallback onTap;
  const _AmortissementButton({required this.onTap});

  @override
  State<_AmortissementButton> createState() => _AmortissementButtonState();
}

class _AmortissementButtonState extends State<_AmortissementButton> {
  bool _hover = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final lifted = _hover || _pressed;
    final dy = _pressed ? 0.0 : (_hover ? -3.0 : 0.0);
    final scale = _pressed ? 0.98 : 1.0;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          transform: Matrix4.identity()
            ..translateByDouble(0.0, dy, 0.0, 1.0)
            ..scaleByDouble(scale, scale, 1.0, 1.0),
          transformAlignment: Alignment.center,
          height: 58,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              colors: [_kPurpleDark, _kPurple, _kPurpleLight],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            boxShadow: [
              BoxShadow(
                color: _kPurple.withValues(alpha: lifted ? 0.55 : 0.35),
                blurRadius: lifted ? 22 : 14,
                offset: Offset(0, lifted ? 10 : 6),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.list_alt_outlined, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Text(
                "Voir le tableau d'amortissement",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(width: 10),
              Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  NOTES CARD
// ---------------------------------------------------------------------------

class _NotesCard extends StatelessWidget {
  final String notes;
  const _NotesCard({required this.notes});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.sticky_note_2_outlined,
                  size: 16, color: AppColors.textSecondary),
              SizedBox(width: 6),
              Text(
                'Notes',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(notes, style: const TextStyle(fontSize: 13, height: 1.4)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  RACHAT BLOCK (kept from previous design for completeness)
// ---------------------------------------------------------------------------

class _RachatBlock extends StatelessWidget {
  final CreditImmobilier credit;
  final NumberFormat money;
  final DateFormat dfMonth;
  const _RachatBlock({
    required this.credit,
    required this.money,
    required this.dfMonth,
  });

  @override
  Widget build(BuildContext context) {
    const purple = _kPurpleLight;
    final economies = credit.economiesRachat;
    final positives = economies > 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: purple.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.swap_horiz_outlined, color: purple, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Rachat',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                  color: purple,
                ),
              ),
              const Spacer(),
              if (credit.rachatPartiel)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: purple.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'PARTIEL',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: purple,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (credit.dateRachat != null)
            _DataRow(
                label: 'Date rachat',
                value: dfMonth.format(credit.dateRachat!)),
          _DataRow(
            label: 'Banque',
            value: credit.banqueRacheteur.isEmpty
                ? '—'
                : credit.banqueRacheteur,
          ),
          _DataRow(
            label: 'Montant racheté',
            value: money.format(credit.montantRachete ?? 0),
          ),
          _DataRow(
            label: 'Nouveau taux',
            value: '${credit.nouveauTaux ?? credit.tauxAnnuel} %',
          ),
          _DataRow(
            label: 'Nouvelle durée',
            value:
                '${credit.nouvelleDureeMois ?? credit.dureeMois} mois',
          ),
          if ((credit.fraisRachat ?? 0) > 0)
            _DataRow(
              label: 'Frais de rachat',
              value: money.format(credit.fraisRachat ?? 0),
            ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: (positives ? _kGreen : const Color(0xFFEF4444))
                  .withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  positives
                      ? Icons.trending_down_outlined
                      : Icons.trending_up_outlined,
                  size: 16,
                  color: positives ? _kGreen : const Color(0xFFEF4444),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    positives
                        ? 'Économies estimées sur les intérêts (frais inclus)'
                        : 'Surcoût estimé (frais inclus)',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                Text(
                  money.format(economies.abs()),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: positives ? _kGreen : const Color(0xFFEF4444),
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

class _DataRow extends StatelessWidget {
  final String label;
  final String value;
  const _DataRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12.5,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
