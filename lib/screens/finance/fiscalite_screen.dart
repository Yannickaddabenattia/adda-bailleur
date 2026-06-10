import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/logement.dart';
import '../../services/fiscalite_service.dart';
import 'fiscal_settings_screen.dart';
import 'sci_list_screen.dart';

/// Formate un taux de prélèvements sociaux en pourcentage français :
/// 0.172 → "17,2 %", 0.186 → "18,6 %". Les libellés sont ainsi toujours
/// alignés sur le taux réellement calculé pour l'année.
String _pctPS(double rate) =>
    '${(rate * 100).toStringAsFixed(1).replaceAll('.', ',')} %';

/// Tableau de bord fiscal — phase 1 (location nue régime réel).
class FiscaliteScreen extends StatefulWidget {
  const FiscaliteScreen({super.key});

  @override
  State<FiscaliteScreen> createState() => _FiscaliteScreenState();
}

class _FiscaliteScreenState extends State<FiscaliteScreen> {
  late int _year;

  @override
  void initState() {
    super.initState();
    // Limite l'année initiale au dernier barème disponible. Sans ça,
    // ouvrir l'écran en 2026+ levait `BaremeIRIndisponible` et plantait.
    final now = DateTime.now().year;
    final dispo = BaremeIR2026.anneesDisponibles;
    _year = (dispo.isEmpty || now <= dispo.last) ? now : dispo.last;
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<FiscaliteService>();
    // Sécurité : si l'année courante sort de la table de barème, on retombe
    // proprement sur la plus récente disponible plutôt que de planter.
    if (!BaremeIR2026.aBaremePour(_year)) {
      return _IndisponibleScreen(
        year: _year,
        anneesDisponibles: BaremeIR2026.anneesDisponibles,
        onPickYear: (y) => setState(() => _year = y),
      );
    }
    final calc = svc.calculer(_year);
    final settings = svc.settings;
    final money = NumberFormat.currency(locale: 'fr_FR', symbol: '€');
    final pct = NumberFormat.decimalPercentPattern(
      locale: 'fr_FR',
      decimalDigits: 1,
    );

    return Scaffold(
      backgroundColor: context.backgroundColor,
      appBar: AppBar(
        title: const Text('Fiscalité'),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_balance_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const SciListScreen(),
              ),
            ),
            tooltip: 'Mes SCI',
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const FiscalSettingsScreen(),
              ),
            ),
            tooltip: 'Paramètres fiscaux',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _YearSelector(
            year: _year,
            onPrev: () => setState(() => _year -= 1),
            onNext: () => setState(() => _year += 1),
          ),
          const SizedBox(height: 16),
          _SyntheseCard(calc: calc, money: money, pct: pct),
          const SizedBox(height: 16),
          _ImpotCard(calc: calc, money: money, parts: settings.parts),
          const SizedBox(height: 16),
          if (calc.reductions.isNotEmpty) ...[
            _ReductionCard(calc: calc, money: money),
            const SizedBox(height: 16),
          ],
          if (calc.deficitImputableGlobal > 0 ||
              calc.deficitReportableFoncier > 0 ||
              calc.reportablesConsommes > 0) ...[
            _DeficitCard(calc: calc, money: money),
            const SizedBox(height: 16),
          ],
          if (calc.details.isEmpty)
            _EmptyState()
          else ...[
            const _SectionLabel('DÉTAIL PAR BIEN'),
            const SizedBox(height: 8),
            for (final d in calc.details)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _LogementCard(
                    detail: d, money: money, annee: calc.annee),
              ),
          ],
          const SizedBox(height: 8),
          _BaremeFooter(annee: BaremeIR2026.annee),
        ],
      ),
    );
  }
}

class _YearSelector extends StatelessWidget {
  final int year;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  const _YearSelector({
    required this.year,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.dividerColor),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onPrev,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: Center(
              child: Column(
                children: [
                  Text(
                    'Année fiscale',
                    style: TextStyle(
                      fontSize: 11,
                      color: context.textSecondaryColor,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '$year',
                    style: TextStyle(
                      fontFamily: 'serif',
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: context.textPrimaryColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }
}

class _SyntheseCard extends StatelessWidget {
  final CalculFiscalAnnuel calc;
  final NumberFormat money;
  final NumberFormat pct;
  const _SyntheseCard({
    required this.calc,
    required this.money,
    required this.pct,
  });

  @override
  Widget build(BuildContext context) {
    final isDeficit = calc.revenuFoncierNetAvantImputation < 0;
    final color = isDeficit ? AppColors.error : AppColors.success;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.10),
            color.withValues(alpha: 0.02),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isDeficit
                    ? Icons.trending_down_rounded
                    : Icons.trending_up_rounded,
                color: color,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                isDeficit ? 'DÉFICIT FONCIER' : 'REVENU FONCIER NET',
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${calc.revenuFoncierNetAvantImputation < 0 ? '−' : ''}${money.format(calc.revenuFoncierNetAvantImputation.abs())}',
            style: TextStyle(
              fontFamily: 'serif',
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 14),
          _Row(
            label: 'Recettes brutes',
            value: money.format(calc.revenuFoncierBrut),
          ),
          _Row(
            label: 'Charges déductibles',
            value: '− ${money.format(calc.chargesTotales)}',
          ),
          _Row(
            label: 'Intérêts d\'emprunt',
            value: '− ${money.format(calc.interetsTotaux)}',
          ),
          _Row(
            label: 'Assurance crédit',
            value: '− ${money.format(calc.assuranceTotale)}',
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final FontWeight? weight;
  const _Row({required this.label, required this.value, this.weight});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
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
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: weight ?? FontWeight.w600,
              color: context.textPrimaryColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _ImpotCard extends StatelessWidget {
  final CalculFiscalAnnuel calc;
  final NumberFormat money;
  final double parts;
  const _ImpotCard({
    required this.calc,
    required this.money,
    required this.parts,
  });

  @override
  Widget build(BuildContext context) {
    final tmiPct = '${(calc.tmiApplique * 100).toStringAsFixed(0)} %';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_outlined,
                  color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'IMPÔT ESTIMÉ',
                style: TextStyle(
                  color: context.textSecondaryColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  'TMI $tmiPct',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            money.format(calc.totalImpotFoncierNet),
            style: TextStyle(
              fontFamily: 'serif',
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: context.textPrimaryColor,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'à payer sur les revenus fonciers ${calc.annee}',
            style: TextStyle(
              fontSize: 12,
              color: context.textSecondaryColor,
            ),
          ),
          const SizedBox(height: 16),
          Divider(color: context.dividerColor, height: 1),
          const SizedBox(height: 12),
          _Row(
            label: 'Revenu foncier imposable',
            value: money.format(calc.revenuFoncierImposable),
            weight: FontWeight.w700,
          ),
          _Row(
            label: 'Impôt sur le revenu (additionnel)',
            value: money.format(calc.impotAdditionnelFoncier),
          ),
          if (calc.reductionAppliquee > 0)
            _Row(
              label: 'Réduction Pinel / Denormandie',
              value: '− ${money.format(calc.reductionAppliquee)}',
            ),
          // Affichage adaptatif des prélèvements sociaux selon le profil :
          // - foncier uniquement → 1 ligne "PS 17,2 %"
          // - meublé uniquement → 1 ligne "PS 18,6 %"
          // - les deux → 2 sous-lignes détaillées
          if (calc.psFoncier > 0 && calc.psMeuble > 0) ...[
            _Row(
              label: 'Prélèvements sociaux fonciers '
                  '${_pctPS(BaremeIR2026.tauxPSFoncierPour(calc.annee))}',
              value: money.format(calc.psFoncier),
            ),
            _Row(
              label: 'Prélèvements sociaux meublé '
                  '${_pctPS(BaremeIR2026.tauxPSMeublePour(calc.annee))}',
              value: money.format(calc.psMeuble),
            ),
          ] else if (calc.psMeuble > 0)
            _Row(
              label: 'Prélèvements sociaux '
                  '${_pctPS(BaremeIR2026.tauxPSMeublePour(calc.annee))}',
              value: money.format(calc.psMeuble),
            )
          else
            _Row(
              label: 'Prélèvements sociaux '
                  '${_pctPS(BaremeIR2026.tauxPSFoncierPour(calc.annee))}',
              value: money.format(calc.prelevementsSociaux),
            ),
          if (calc.deficitImputableGlobal > 0) ...[
            const SizedBox(height: 6),
            _Row(
              label: 'Déficit imputé sur revenu global',
              value: '− ${money.format(calc.deficitImputableGlobal)}',
            ),
          ],
          const SizedBox(height: 12),
          Divider(color: context.dividerColor, height: 1),
          const SizedBox(height: 10),
          _Row(
            label: 'IR total du foyer (estimé)',
            value: money.format(calc.impotRevenuFoyerNet),
            weight: FontWeight.w700,
          ),
          _Row(
            label: 'À payer (IR foyer + PS fonciers)',
            value: money.format(calc.totalImpotFoyer),
            weight: FontWeight.w700,
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: context.dividerColor.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'Calcul indicatif basé sur le barème ${BaremeIR2026.annee} '
              '(parts : ${parts.toString().replaceAll('.', ',')}). '
              'Le résultat final dépend de votre déclaration complète.',
              style: TextStyle(
                fontSize: 11,
                color: context.textSecondaryColor,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReductionCard extends StatelessWidget {
  final CalculFiscalAnnuel calc;
  final NumberFormat money;
  const _ReductionCard({required this.calc, required this.money});

  @override
  Widget build(BuildContext context) {
    final color = const Color(0xFF7C3AED);
    final plafonne = calc.reductionBrute - calc.reductionAppliquee;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.discount_outlined, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                'RÉDUCTION D\'IMPÔT',
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '− ${money.format(calc.reductionAppliquee)}',
            style: TextStyle(
              fontFamily: 'serif',
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 12),
          for (final r in calc.reductions) ...[
            _Row(
              label: '${r.logement.libelle} · ${r.dispositif.label} '
                  '(${r.dureeAnnees} ans)',
              value: r.dansLaFenetre
                  ? money.format(r.reductionAnnuelle)
                  : 'hors fenêtre',
            ),
          ],
          const SizedBox(height: 8),
          if (calc.reductionBrute != calc.reductionAppliquee)
            _Row(
              label: 'Réduction brute',
              value: money.format(calc.reductionBrute),
            ),
          if (plafonne > 0)
            _Row(
              label: 'Plafonné (niches)',
              value: '− ${money.format(plafonne)}',
            ),
          const SizedBox(height: 8),
          Text(
            'Plafond global des niches : '
            '${money.format(BaremeIR2026.plafondGlobalNichesFiscales)}/an. '
            'Disponible : ${money.format(calc.plafondRestant)}.',
            style: TextStyle(
              fontSize: 11,
              color: context.textSecondaryColor,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeficitCard extends StatelessWidget {
  final CalculFiscalAnnuel calc;
  final NumberFormat money;
  const _DeficitCard({required this.calc, required this.money});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.swap_vert_rounded,
                  color: AppColors.accent, size: 20),
              SizedBox(width: 8),
              Text(
                'GESTION DU DÉFICIT',
                style: TextStyle(
                  color: AppColors.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (calc.deficitImputableGlobal > 0)
            _Row(
              label: 'Déficit imputable sur revenu global',
              value: money.format(calc.deficitImputableGlobal),
              weight: FontWeight.w700,
            ),
          if (calc.deficitReportableFoncier > 0)
            _Row(
              label: 'Reportable sur fonciers (10 ans)',
              value: money.format(calc.deficitReportableFoncier),
              weight: FontWeight.w700,
            ),
          if (calc.reportablesConsommes > 0)
            _Row(
              label: 'Reportables consommés cette année',
              value: '− ${money.format(calc.reportablesConsommes)}',
            ),
          const SizedBox(height: 8),
          Text(
            'Plafond global : ${money.format(BaremeIR2026.plafondDeficitImputableGlobal)}.',
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

class _LogementCard extends StatelessWidget {
  final DetailFiscalLogement detail;
  final NumberFormat money;
  final int annee;
  const _LogementCard({
    required this.detail,
    required this.money,
    required this.annee,
  });

  @override
  Widget build(BuildContext context) {
    final isDeficit = detail.enDeficit;
    final color = isDeficit ? AppColors.error : AppColors.success;
    return Container(
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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.home_outlined,
                    color: AppColors.primary, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      detail.logement.libelle,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: context.textPrimaryColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      detail.logement.ville,
                      style: TextStyle(
                        fontSize: 11,
                        color: context.textSecondaryColor,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${detail.revenuNet < 0 ? '−' : ''}${money.format(detail.revenuNet.abs())}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: color,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Divider(height: 1, color: context.dividerColor),
          const SizedBox(height: 8),
          if (detail.logement.dispositif != DispositifFiscal.aucun) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const Icon(Icons.local_offer_outlined,
                      size: 14, color: AppColors.accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Dispositif : ${detail.logement.dispositif.label}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          _MiniRow(
            label: 'Recettes brutes',
            value: money.format(detail.recettesBrutes),
          ),
          if (detail.tauxAbattementBorloo > 0)
            _MiniRow(
              label:
                  'Abattement Borloo (${(detail.tauxAbattementBorloo * 100).toStringAsFixed(0)} %)',
              value: '− ${money.format(detail.abattementBorloo)}',
              highlight: true,
            ),
          if (detail.tauxAbattementBorloo > 0)
            _MiniRow(
              label: 'Recettes imposables',
              value: money.format(detail.recettesImposables),
              bold: true,
            ),
          _MiniRow(
            label: 'Charges',
            value: '− ${money.format(detail.charges)}',
          ),
          if (detail.interets > 0)
            _MiniRow(
              label: 'Intérêts crédit',
              value: '− ${money.format(detail.interets)}',
            ),
          if (detail.assuranceCredit > 0)
            _MiniRow(
              label: 'Assurance crédit',
              value: '− ${money.format(detail.assuranceCredit)}',
            ),
          if (detail.logement.dispositif.isPinelDenormandie &&
              detail.logement.dateAcquisition != null)
            Builder(builder: (ctx) {
              final svc = ctx.read<FiscaliteService>();
              final r = svc.reductionPourLogement(detail.logement, annee);
              if (r == null || r.reductionAnnuelle <= 0) {
                return const SizedBox.shrink();
              }
              return _MiniRow(
                label: 'Réduction ${detail.logement.dispositif.label}',
                value: '− ${money.format(r.reductionAnnuelle)} (sur IR)',
                highlight: true,
              );
            }),
        ],
      ),
    );
  }
}

class _MiniRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final bool highlight;
  const _MiniRow({
    required this.label,
    required this.value,
    this.bold = false,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = highlight
        ? AppColors.accent
        : (bold ? context.textPrimaryColor : context.textSecondaryColor);
    final valueColor = highlight ? AppColors.accent : context.textPrimaryColor;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: bold || highlight ? FontWeight.w700 : null,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              color: valueColor,
              fontWeight: bold || highlight
                  ? FontWeight.w800
                  : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        color: context.textSecondaryColor,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.dividerColor),
      ),
      child: Column(
        children: [
          Icon(Icons.receipt_long_outlined,
              size: 48,
              color: context.textSecondaryColor.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text(
            'Aucun bien éligible',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: context.textPrimaryColor,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Configure le statut fiscal de tes biens en location nue pour '
            'voir le calcul d\'impôt.',
            style: TextStyle(
              fontSize: 12,
              color: context.textSecondaryColor,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _BaremeFooter extends StatelessWidget {
  final int annee;
  const _BaremeFooter({required this.annee});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
      child: Text(
        'Barème IR $annee · '
        'PS foncier ${_pctPS(BaremeIR2026.tauxPSFoncierPour(annee))} · '
        'PS meublé ${_pctPS(BaremeIR2026.tauxPSMeublePour(annee))} · '
        'Plafond QF ${NumberFormat.decimalPattern('fr_FR').format(BaremeIR2026.plafondQuotientFamilialDemiPart)} €/demi-part',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          color: context.textSecondaryColor,
        ),
      ),
    );
  }
}

/// Écran de repli affiché quand l'année sélectionnée n'a pas de barème IR
/// dans la table interne (avant 2006 ou après 2025 actuellement).
class _IndisponibleScreen extends StatelessWidget {
  final int year;
  final List<int> anneesDisponibles;
  final ValueChanged<int> onPickYear;

  const _IndisponibleScreen({
    required this.year,
    required this.anneesDisponibles,
    required this.onPickYear,
  });

  @override
  Widget build(BuildContext context) {
    final min = anneesDisponibles.first;
    final max = anneesDisponibles.last;
    return Scaffold(
      backgroundColor: context.backgroundColor,
      appBar: AppBar(title: const Text('Fiscalité')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.calculate_outlined,
                size: 64,
                color: Color(0xFF7C3AED),
              ),
              const SizedBox(height: 12),
              Text(
                'Barème IR indisponible pour $year',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: context.textPrimaryColor,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'L\'application contient les barèmes des revenus $min à $max. '
                'Sélectionne une année dans cette plage pour voir tes impôts.',
                style: TextStyle(
                  fontSize: 13,
                  color: context.textSecondaryColor,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                icon: const Icon(Icons.history_rounded),
                onPressed: () => onPickYear(max),
                label: Text('Voir l\'année $max'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
