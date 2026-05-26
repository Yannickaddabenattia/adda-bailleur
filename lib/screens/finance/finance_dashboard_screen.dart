import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/hover_card.dart';
import '../../models/logement.dart';
import '../../services/credit_service.dart';
import '../../services/depense_service.dart';
import '../../services/fiscalite_service.dart';
import '../../services/locataire_service.dart';
import '../../services/logement_service.dart';
import '../../services/quittance_service.dart';
import '../../services/revision_loyer_service.dart';
import '../../services/sci_service.dart';
import '../backup/backup_screen.dart';
import '../quittances/quittance_form_screen.dart';
import 'credit_list_screen.dart';
import 'depense_form_screen.dart';
import 'depense_list_screen.dart';
import 'fiscalite_screen.dart';
import 'loyers_en_retard_screen.dart';
import 'sorties_detail_screen.dart';

class FinanceDashboardScreen extends StatefulWidget {
  const FinanceDashboardScreen({super.key});

  @override
  State<FinanceDashboardScreen> createState() =>
      _FinanceDashboardScreenState();
}

class _FinanceDashboardScreenState extends State<FinanceDashboardScreen> {
  String? _logementId;
  late int _year;

  static const List<String> _moisCourts = [
    'J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D',
  ];
  static const List<String> _moisLongs = [
    'JAN', 'FÉV', 'MAR', 'AVR', 'MAI', 'JUIN',
    'JUIL', 'AOÛ', 'SEP', 'OCT', 'NOV', 'DÉC',
  ];

  @override
  void initState() {
    super.initState();
    _year = DateTime.now().year;
  }

  @override
  Widget build(BuildContext context) {
    final logements = context.watch<LogementService>().all;
    final locataires = context.watch<LocataireService>().all;
    final quittances = context.watch<QuittanceService>().all;
    final depensesSvc = context.watch<DepenseService>();
    final creditsSvc = context.watch<CreditService>();
    final revisionsSvc = context.watch<RevisionLoyerService>();
    final fiscaliteSvc = context.watch<FiscaliteService>();

    final money = NumberFormat.currency(locale: 'fr_FR', symbol: '€');

    final filtered =
        _logementId == null ? logements : logements.where((l) => l.id == _logementId).toList();

    final now = DateTime.now();
    final maxMonth =
        _year < now.year ? 12 : (_year == now.year ? now.month : 0);
    final monthsLabel = '${_moisLongs[0]} — ${maxMonth >= 1 ? _moisLongs[maxMonth - 1] : '—'} · $maxMonth MOIS';

    var totalReels = 0.0;
    var totalAttendus = 0.0;
    var totalDepenses = 0.0;
    var totalCredits = 0.0;
    var quittancesDues = 0;
    final monthlyReels = <int, double>{for (var m = 1; m <= 12; m++) m: 0};
    final monthlyAttendus = <int, double>{for (var m = 1; m <= 12; m++) m: 0};
    final perLogementReels = <String, double>{};
    final perLogementAttendus = <String, double>{};

    for (final l in filtered) {
      perLogementReels[l.id] = 0;
      perLogementAttendus[l.id] = 0;

      // Une seule quittance par (logement, mois) : si plusieurs existent (un par
      // colocataire), on garde la plus élevée pour ne pas doubler le revenu.
      final byMonth = <int, double>{};
      for (final q in quittances.where(
          (q) => q.logementId == l.id && q.periodYear == _year)) {
        final prev = byMonth[q.periodMonth];
        if (prev == null || q.total > prev) {
          byMonth[q.periodMonth] = q.total;
        }
      }
      for (final entry in byMonth.entries) {
        totalReels += entry.value;
        monthlyReels[entry.key] = (monthlyReels[entry.key] ?? 0) + entry.value;
        perLogementReels[l.id] = (perLogementReels[l.id] ?? 0) + entry.value;
      }

      final occupants =
          locataires.where((loc) => loc.logementIds.contains(l.id)).toList();
      for (var m = 1; m <= maxMonth; m++) {
        if (occupants.isEmpty) continue;
        final monthDate = DateTime(_year, m, 1);
        final daysInMonth = DateTime(_year, m + 1, 0).day;
        // Compte les jours du mois où au moins un locataire est présent
        // (dateEntree <= jour <= dateSortie). Prorata pour les mois d'entrée/sortie.
        var occupiedDays = 0;
        for (var d = 1; d <= daysInMonth; d++) {
          final day = DateTime(_year, m, d);
          final anyActive = occupants.any((loc) {
            final de = loc.dateEntree;
            if (de != null && day.isBefore(DateTime(de.year, de.month, de.day))) {
              return false;
            }
            final ds = loc.dateSortie;
            if (ds != null && day.isAfter(DateTime(ds.year, ds.month, ds.day))) {
              return false;
            }
            return true;
          });
          if (anyActive) occupiedDays++;
        }
        if (occupiedDays == 0) continue;
        final eff = revisionsSvc.loyerEffectifAt(
          logement: l,
          date: monthDate,
        );
        final du = eff.total * occupiedDays / daysInMonth;
        totalAttendus += du;
        monthlyAttendus[m] = (monthlyAttendus[m] ?? 0) + du;
        perLogementAttendus[l.id] = (perLogementAttendus[l.id] ?? 0) + du;

        final exists = quittances.any((q) =>
            q.logementId == l.id &&
            q.periodYear == _year &&
            q.periodMonth == m);
        if (!exists) quittancesDues += 1;
      }

      totalDepenses += depensesSvc.totalForLogementYear(l.id, _year);
      totalCredits += creditsSvc.annualPaymentsForLogement(l.id, _year);
    }

    // Impôts fonciers payés en année N pour les revenus de N-1.
    // Calcul global du foyer : surplus IR (impôt avec foncier - sans foncier)
    // + prélèvements sociaux 17,2 %. Affiché uniquement quand on ne filtre
    // pas sur un logement précis (la fiscalité est globale).
    final calcFiscalAnneeNm1 =
        _logementId == null ? fiscaliteSvc.calculer(_year - 1) : null;
    final surplusIRFoncier =
        calcFiscalAnneeNm1?.impotAdditionnelFoncierNet ?? 0.0;
    final prelevementsSociaux =
        calcFiscalAnneeNm1?.prelevementsSociaux ?? 0.0;
    final impotFoncier = surplusIRFoncier + prelevementsSociaux;

    // IS + PFU des SCI à l'IS (vue globale uniquement : la fiscalité société
    // est par nature détachée d'un logement isolé).
    final sciSvc = context.watch<SCIService>();
    final impotSCI = _logementId == null ? sciSvc.totalCoutFiscalIS(_year) : 0.0;

    final sorties = totalDepenses + totalCredits + impotFoncier + impotSCI;
    final bilan = totalReels - sorties;
    final retard = math.max(0.0, totalAttendus - totalReels);
    final bilanSiRecouvre = bilan + retard;
    final pctEncaisse =
        totalAttendus > 0 ? ((totalReels / totalAttendus) * 100).round() : 0;
    final loyersOK = totalAttendus == 0 || retard <= 0.5;

    final maxMonthly = [
      ...monthlyReels.values,
      ...monthlyAttendus.values,
    ].fold<double>(0, (m, v) => v > m ? v : m);
    final chartMax = maxMonthly == 0 ? 100.0 : maxMonthly * 1.3;

    final perfEntries = filtered
        .map((l) => _PerfEntry(
              logement: l,
              reels: perLogementReels[l.id] ?? 0,
              attendus: perLogementAttendus[l.id] ?? 0,
              isVacant: !locataires.any((loc) => loc.logementIds.contains(l.id)),
            ))
        .toList()
      ..sort((a, b) => b.attendus.compareTo(a.attendus));

    return Scaffold(
      backgroundColor: context.backgroundColor,
      body: Column(
        children: [
          _Hero(
            year: _year,
            monthsLabel: monthsLabel,
            onPrev: () => setState(() => _year -= 1),
            onNext: () => setState(() => _year += 1),
            onBack: Navigator.of(context).canPop()
                ? () => Navigator.of(context).maybePop()
                : null,
            onExport: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BackupScreen()),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                _LogementFilterPill(
                  value: _logementId,
                  logements: logements,
                  onChanged: (v) => setState(() => _logementId = v),
                ),
                const SizedBox(height: 16),
                _BilanNetCard(
                  bilan: bilan,
                  encaisse: totalReels,
                  sorties: sorties,
                  retard: retard,
                  bilanSiRecouvre: bilanSiRecouvre,
                  money: money,
                ),
                const SizedBox(height: 16),
                _KpiGrid(
                  encaisse: totalReels,
                  pctEncaisse: pctEncaisse,
                  retard: retard,
                  quittancesDues: quittancesDues,
                  attendus: totalAttendus,
                  attendusPerMonth: maxMonth > 0 ? totalAttendus / maxMonth : 0,
                  sorties: sorties,
                  // Dépenses, crédits et impôt foncier sont calculés sur
                  // l'année entière (12 mois), donc la moyenne mensuelle se
                  // divise toujours par 12 — sinon l'affichage gonfle au
                  // prorata des mois écoulés (ex: total annuel / 5 en mai).
                  sortiesPerMonth: sorties / 12,
                  money: money,
                  hasArrears: !loyersOK,
                  onTapRetards: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => LoyersEnRetardScreen(
                        year: _year,
                        logementId: _logementId,
                      ),
                    ),
                  ),
                  onTapSorties: sorties > 0
                      ? () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => SortiesDetailScreen(
                                year: _year,
                                logementId: _logementId,
                                surplusIRFoncier: surplusIRFoncier,
                                prelevementsSociaux: prelevementsSociaux,
                              ),
                            ),
                          )
                      : null,
                ),
                const SizedBox(height: 20),
                _MonthlyChartCard(
                  monthlyReels: monthlyReels,
                  monthlyAttendus: monthlyAttendus,
                  chartMax: chartMax,
                  maxMonth: maxMonth,
                  monthLabels: _moisCourts,
                ),
                const SizedBox(height: 20),
                if (perfEntries.isNotEmpty)
                  _PerformanceCard(entries: perfEntries, money: money),
                const SizedBox(height: 24),
                _SectionLabel('ACCÈS RAPIDES'),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _AccessTile(
                        icon: Icons.schedule_rounded,
                        color: AppColors.error,
                        label: 'Loyers en retard',
                        badgeCount: quittancesDues,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => LoyersEnRetardScreen(
                              year: _year,
                              logementId: _logementId,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _AccessTile(
                        icon: Icons.add_rounded,
                        color: AppColors.accent,
                        label: 'Ajouter dépense',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => DepenseFormScreen(
                              initialLogementId: _logementId,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _AccessTile(
                        icon: Icons.description_outlined,
                        color: AppColors.success,
                        label: 'Générer quittance',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const QuittanceFormScreen(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _AccessTile(
                        icon: Icons.file_download_outlined,
                        color: AppColors.primary,
                        label: 'Exporter bilan',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const BackupScreen()),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _AccessLine(
                  icon: Icons.account_balance_outlined,
                  color: AppColors.primary,
                  label: 'Crédits immobiliers',
                  subtitle: 'Capital, taux, durée, amortissement',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CreditListScreen(logementId: _logementId),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _AccessLine(
                  icon: Icons.calculate_outlined,
                  color: const Color(0xFF7C3AED),
                  label: 'Fiscalité',
                  subtitle: 'Revenu foncier net, IR + PS, déficit',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const FiscaliteScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _AccessLine(
                  icon: Icons.trending_down_rounded,
                  color: AppColors.error,
                  label: 'Toutes les dépenses',
                  subtitle: 'Charges, taxes, réparations, justificatifs',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DepenseListScreen(logementId: _logementId),
                    ),
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

class _PerfEntry {
  final Logement logement;
  final double reels;
  final double attendus;
  final bool isVacant;
  const _PerfEntry({
    required this.logement,
    required this.reels,
    required this.attendus,
    required this.isVacant,
  });
}

class _Hero extends StatelessWidget {
  final int year;
  final String monthsLabel;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback? onBack;
  final VoidCallback onExport;
  const _Hero({
    required this.year,
    required this.monthsLabel,
    required this.onPrev,
    required this.onNext,
    required this.onBack,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F1B3A),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      padding: EdgeInsets.fromLTRB(20, topInset + 12, 20, 22),
      child: Column(
        children: [
          Row(
            children: [
              if (onBack != null)
                _CircleIconButton(
                    icon: Icons.arrow_back_rounded, onTap: onBack!)
              else
                const SizedBox(width: 40, height: 40),
              const Expanded(
                child: Center(
                  child: Text(
                    'Tableau de bord',
                    style: TextStyle(
                      fontFamily: 'serif',
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              _CircleIconButton(
                icon: Icons.file_download_outlined,
                onTap: onExport,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: onPrev,
                icon: const Icon(Icons.chevron_left_rounded,
                    color: Colors.white70, size: 28),
              ),
              Text(
                '$year',
                style: const TextStyle(
                  fontFamily: 'serif',
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                ),
              ),
              IconButton(
                onPressed: onNext,
                icon: const Icon(Icons.chevron_right_rounded,
                    color: Colors.white70, size: 28),
              ),
            ],
          ),
          Text(
            monthsLabel,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleIconButton({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 26,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

class _LogementFilterPill extends StatelessWidget {
  final String? value;
  final List<Logement> logements;
  final ValueChanged<String?> onChanged;
  const _LogementFilterPill({
    required this.value,
    required this.logements,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selected = value == null
        ? 'Tous mes logements'
        : logements.firstWhere((l) => l.id == value, orElse: () => logements.first).libelle;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        final result = await showModalBottomSheet<String?>(
          context: context,
          backgroundColor: context.surfaceColor,
          shape: const RoundedRectangleBorder(
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (_) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.apps_rounded),
                  title: const Text('Tous mes logements'),
                  onTap: () => Navigator.of(context).pop(null),
                ),
                const Divider(height: 1),
                ...logements.map(
                  (l) => ListTile(
                    leading: const Icon(Icons.home_outlined),
                    title: Text(l.libelle),
                    subtitle: Text(l.ville),
                    onTap: () => Navigator.of(context).pop(l.id),
                  ),
                ),
              ],
            ),
          ),
        );
        if (result != null || value != null) {
          onChanged(result);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: context.surfaceColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.dividerColor),
        ),
        child: Row(
          children: [
            Icon(Icons.filter_alt_outlined,
                size: 18, color: context.textSecondaryColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                selected,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: context.textPrimaryColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.keyboard_arrow_down_rounded,
                color: context.textSecondaryColor),
          ],
        ),
      ),
    );
  }
}

class _BilanNetCard extends StatelessWidget {
  final double bilan;
  final double encaisse;
  final double sorties;
  final double retard;
  final double bilanSiRecouvre;
  final NumberFormat money;
  const _BilanNetCard({
    required this.bilan,
    required this.encaisse,
    required this.sorties,
    required this.retard,
    required this.bilanSiRecouvre,
    required this.money,
  });

  @override
  Widget build(BuildContext context) {
    final isPerte = bilan < 0;
    final color = isPerte ? AppColors.error : AppColors.success;
    final total = encaisse + sorties;
    final greenPct = total > 0 ? (encaisse / total).clamp(0.0, 1.0) : 0.0;
    return Container(
      padding: const EdgeInsets.all(18),
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
              Text(
                'BILAN NET',
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
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isPerte
                          ? Icons.arrow_drop_down_rounded
                          : Icons.arrow_drop_up_rounded,
                      color: color,
                      size: 18,
                    ),
                    Text(
                      isPerte ? 'En perte' : 'En bénéfice',
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${bilan < 0 ? '−' : ''}${money.format(bilan.abs())}',
            style: TextStyle(
              fontFamily: 'serif',
              fontSize: 36,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: SizedBox(
              height: 8,
              child: Row(
                children: [
                  Expanded(
                    flex: (greenPct * 1000).round().clamp(0, 1000),
                    child: Container(color: AppColors.success),
                  ),
                  Expanded(
                    flex: ((1 - greenPct) * 1000).round().clamp(0, 1000),
                    child: Container(color: AppColors.error.withValues(alpha: 0.25)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _Dot(color: AppColors.success),
              const SizedBox(width: 6),
              Text(
                'Encaissé · ${money.format(encaisse)}',
                style: TextStyle(
                  color: context.textSecondaryColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              _Dot(color: AppColors.error),
              const SizedBox(width: 6),
              Text(
                'Sorties · ${money.format(sorties)}',
                style: TextStyle(
                  color: context.textSecondaryColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (retard > 0.5) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4D6),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.flash_on_rounded,
                        color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          color: Color(0xFF0F1B3A),
                          fontSize: 13,
                          height: 1.35,
                        ),
                        children: [
                          const TextSpan(text: 'Recouvrer '),
                          TextSpan(
                            text: money.format(retard),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const TextSpan(
                              text: ' de loyers en retard ferait passer le bilan à '),
                          TextSpan(
                            text:
                                '${bilanSiRecouvre >= 0 ? '+' : ''}${money.format(bilanSiRecouvre)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.success,
                            ),
                          ),
                          const TextSpan(text: '.'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  const _Dot({required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  final double encaisse;
  final int pctEncaisse;
  final double retard;
  final int quittancesDues;
  final double attendus;
  final double attendusPerMonth;
  final double sorties;
  final double sortiesPerMonth;
  final NumberFormat money;
  final bool hasArrears;
  final VoidCallback? onTapRetards;
  final VoidCallback? onTapSorties;
  const _KpiGrid({
    required this.encaisse,
    required this.pctEncaisse,
    required this.retard,
    required this.quittancesDues,
    required this.attendus,
    required this.attendusPerMonth,
    required this.sorties,
    required this.sortiesPerMonth,
    required this.money,
    required this.hasArrears,
    this.onTapRetards,
    this.onTapSorties,
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
                label: 'Encaissés',
                value: money.format(encaisse),
                detail: '$pctEncaisse % de l\'attendu',
                valueColor: AppColors.success,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _KpiTile(
                icon: Icons.error_outline_rounded,
                color: AppColors.error,
                label: 'En retard',
                value: money.format(retard),
                detail: '$quittancesDues quittance${quittancesDues > 1 ? 's' : ''} due${quittancesDues > 1 ? 's' : ''}',
                valueColor: AppColors.error,
                highlight: hasArrears,
                onTap: quittancesDues > 0 ? onTapRetards : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _KpiTile(
                icon: Icons.event_outlined,
                color: AppColors.primary,
                label: 'Attendus',
                value: money.format(attendus),
                detail:
                    '${money.format(attendusPerMonth)}/mois théorique',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _KpiTile(
                icon: Icons.trending_down_rounded,
                color: AppColors.accent,
                label: 'Dépenses + crédits',
                value: money.format(sorties),
                detail: '${money.format(sortiesPerMonth)}/mois moyen',
                onTap: onTapSorties,
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
  final String detail;
  final Color? valueColor;
  final bool highlight;
  final VoidCallback? onTap;
  const _KpiTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.detail,
    this.valueColor,
    this.highlight = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: context.textSecondaryColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: valueColor ?? context.textPrimaryColor,
          ),
        ),
        const SizedBox(height: 2),
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
    );
    final borderColor = highlight
        ? AppColors.error.withValues(alpha: 0.45)
        : context.dividerColor;
    if (onTap == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.surfaceColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: highlight ? 1.5 : 1),
        ),
        child: content,
      );
    }
    return HoverCard(
      onTap: onTap,
      accent: color,
      borderRadius: BorderRadius.circular(16),
      background: context.surfaceColor,
      borderColor: borderColor,
      padding: const EdgeInsets.all(14),
      child: content,
    );
  }
}

class _MonthlyChartCard extends StatelessWidget {
  final Map<int, double> monthlyReels;
  final Map<int, double> monthlyAttendus;
  final double chartMax;
  final int maxMonth;
  final List<String> monthLabels;
  const _MonthlyChartCard({
    required this.monthlyReels,
    required this.monthlyAttendus,
    required this.chartMax,
    required this.maxMonth,
    required this.monthLabels,
  });

  @override
  Widget build(BuildContext context) {
    final attenduMoyen = () {
      var sum = 0.0;
      var n = 0;
      for (var m = 1; m <= maxMonth; m++) {
        final v = monthlyAttendus[m] ?? 0;
        if (v > 0) {
          sum += v;
          n += 1;
        }
      }
      return n == 0 ? 0.0 : sum / n;
    }();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Évolution mensuelle',
            style: TextStyle(
              fontFamily: 'serif',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: context.textPrimaryColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Loyers encaissés vs attendus',
            style: TextStyle(
              fontSize: 12,
              color: context.textSecondaryColor,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 180,
            child: CustomPaint(
              painter: _ChartPainter(
                monthlyReels: monthlyReels,
                attenduMoyen: attenduMoyen,
                chartMax: chartMax,
                maxMonth: maxMonth,
                axisColor: context.dividerColor,
                gridColor: context.dividerColor.withValues(alpha: 0.4),
                textColor: context.textSecondaryColor,
                primary: AppColors.primary,
                green: AppColors.success,
                future: context.dividerColor.withValues(alpha: 0.6),
                monthLabels: monthLabels,
              ),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _LegendDot(color: AppColors.success, label: 'Encaissé'),
              const SizedBox(width: 14),
              _LegendDash(color: AppColors.primary, label: 'Attendu'),
              const Spacer(),
              _LegendDot(
                color: context.dividerColor,
                label: 'À venir',
                isFuture: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  final Map<int, double> monthlyReels;
  final double attenduMoyen;
  final double chartMax;
  final int maxMonth;
  final Color axisColor;
  final Color gridColor;
  final Color textColor;
  final Color primary;
  final Color green;
  final Color future;
  final List<String> monthLabels;

  _ChartPainter({
    required this.monthlyReels,
    required this.attenduMoyen,
    required this.chartMax,
    required this.maxMonth,
    required this.axisColor,
    required this.gridColor,
    required this.textColor,
    required this.primary,
    required this.green,
    required this.future,
    required this.monthLabels,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const leftPad = 28.0;
    const bottomPad = 22.0;
    const topPad = 8.0;
    final chartW = size.width - leftPad;
    final chartH = size.height - bottomPad - topPad;

    // grid + y labels
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    final labelStyle = TextStyle(color: textColor, fontSize: 9);
    final ticks = [0.0, chartMax * 1 / 3, chartMax * 2 / 3, chartMax];
    for (final v in ticks) {
      final y = topPad + chartH - (v / chartMax) * chartH;
      canvas.drawLine(Offset(leftPad, y), Offset(size.width, y), gridPaint);
      final tp = TextPainter(
        text: TextSpan(
          text: v >= 1000
              ? '${(v / 1000).toStringAsFixed(0)}k'
              : v.toInt().toString(),
          style: labelStyle,
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(leftPad - tp.width - 4, y - tp.height / 2));
    }

    // dashed attendu line
    if (attenduMoyen > 0) {
      final y = topPad + chartH - (attenduMoyen / chartMax) * chartH;
      final dashPaint = Paint()
        ..color = primary
        ..strokeWidth = 1.5;
      var x = leftPad;
      while (x < size.width) {
        canvas.drawLine(Offset(x, y), Offset(x + 6, y), dashPaint);
        x += 10;
      }
      final tp = TextPainter(
        text: TextSpan(
          text:
              'attendu ${attenduMoyen.toStringAsFixed(0)} €',
          style: TextStyle(
            color: primary,
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(size.width - tp.width - 2, y - tp.height - 2));
    }

    // bars
    final slotW = chartW / 12;
    final barW = slotW * 0.45;
    for (var m = 1; m <= 12; m++) {
      final cx = leftPad + (m - 0.5) * slotW;
      final isFuture = m > maxMonth;
      final v = monthlyReels[m] ?? 0;
      final barH = v > 0 ? (v / chartMax) * chartH : 4.0;
      final paint = Paint()
        ..color = isFuture
            ? future
            : (v > 0 ? green : future)
        ..style = PaintingStyle.fill;
      final rect = RRect.fromRectAndCorners(
        Rect.fromCenter(
          center: Offset(cx, topPad + chartH - barH / 2),
          width: barW,
          height: barH,
        ),
        topLeft: const Radius.circular(3),
        topRight: const Radius.circular(3),
      );
      canvas.drawRRect(rect, paint);

      // month label
      final mp = TextPainter(
        text: TextSpan(
          text: monthLabels[m - 1],
          style: TextStyle(
            color: isFuture ? future : textColor,
            fontSize: 10,
            fontWeight: m == maxMonth ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      mp.paint(canvas,
          Offset(cx - mp.width / 2, topPad + chartH + 6));
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) =>
      old.chartMax != chartMax ||
      old.maxMonth != maxMonth ||
      old.attenduMoyen != attenduMoyen ||
      old.monthlyReels.toString() != monthlyReels.toString();
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  final bool isFuture;
  const _LegendDot({
    required this.color,
    required this.label,
    this.isFuture = false,
  });
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
            border: isFuture ? Border.all(color: color) : null,
          ),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
              fontSize: 11,
              color: context.textSecondaryColor,
              fontWeight: FontWeight.w600,
            )),
      ],
    );
  }
}

class _LegendDash extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDash({required this.color, required this.label});
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 16,
          child: CustomPaint(
            size: const Size(16, 2),
            painter: _DashLinePainter(color: color),
          ),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
              fontSize: 11,
              color: context.textSecondaryColor,
              fontWeight: FontWeight.w600,
            )),
      ],
    );
  }
}

class _DashLinePainter extends CustomPainter {
  final Color color;
  _DashLinePainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, size.height / 2),
          Offset(x + 4, size.height / 2), p);
      x += 6;
    }
  }

  @override
  bool shouldRepaint(covariant _DashLinePainter old) => old.color != color;
}

class _PerformanceCard extends StatelessWidget {
  final List<_PerfEntry> entries;
  final NumberFormat money;
  const _PerformanceCard({required this.entries, required this.money});

  @override
  Widget build(BuildContext context) {
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
          Text(
            'Performance par logement',
            style: TextStyle(
              fontFamily: 'serif',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: context.textPrimaryColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Recouvrement YTD',
            style: TextStyle(
              fontSize: 12,
              color: context.textSecondaryColor,
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < entries.length; i++) ...[
            _PerfRow(entry: entries[i], money: money),
            if (i < entries.length - 1)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Divider(height: 1, color: context.dividerColor),
              ),
          ],
        ],
      ),
    );
  }
}

class _PerfRow extends StatelessWidget {
  final _PerfEntry entry;
  final NumberFormat money;
  const _PerfRow({required this.entry, required this.money});

  @override
  Widget build(BuildContext context) {
    final pct = entry.attendus > 0
        ? (entry.reels / entry.attendus).clamp(0.0, 1.0)
        : 0.0;
    final iconBg = entry.isVacant
        ? AppColors.accent.withValues(alpha: 0.18)
        : AppColors.primary.withValues(alpha: 0.12);
    final iconColor = entry.isVacant ? AppColors.accent : AppColors.primary;
    final amountColor = entry.isVacant
        ? AppColors.accent
        : (pct >= 0.99 ? AppColors.success : context.textPrimaryColor);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.home_outlined, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                entry.logement.libelle,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: context.textPrimaryColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (entry.isVacant) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'VACANT',
                  style: TextStyle(
                    color: AppColors.accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Text(
              '${money.format(entry.reels)} / ${money.format(entry.attendus)}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: amountColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: SizedBox(
            height: 4,
            child: Stack(
              children: [
                Container(color: context.dividerColor),
                FractionallySizedBox(
                  widthFactor: pct == 0 && entry.isVacant ? 1 : pct,
                  child: Container(
                    color: entry.isVacant
                        ? AppColors.accent.withValues(alpha: 0.45)
                        : (pct >= 0.99
                            ? AppColors.success
                            : AppColors.success),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 0, 0),
      child: Text(
        label,
        style: TextStyle(
          color: context.textSecondaryColor,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _AccessTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final int? badgeCount;
  final VoidCallback onTap;
  const _AccessTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
    this.badgeCount,
  });

  @override
  Widget build(BuildContext context) {
    return HoverCard(
      onTap: onTap,
      accent: color,
      borderRadius: BorderRadius.circular(16),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              if (badgeCount != null && badgeCount! > 0)
                Positioned(
                  top: -4,
                  right: -4,
                  child: Container(
                    width: 18,
                    height: 18,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: AppColors.error,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$badgeCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.textPrimaryColor,
              ),
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }
}

class _AccessLine extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  const _AccessLine({
    required this.icon,
    required this.color,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return HoverCard(
      onTap: onTap,
      accent: color,
      borderRadius: BorderRadius.circular(16),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: context.textPrimaryColor)),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 12,
                        color: context.textSecondaryColor)),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: context.textSecondaryColor),
        ],
      ),
    );
  }
}
