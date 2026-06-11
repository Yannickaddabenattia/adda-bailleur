import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/currency_format.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hover_card.dart';
import '../../widgets/backup_status_badge.dart';
import '../../widgets/foreign_backup_banner.dart';
import '../../models/locataire.dart';
import '../../models/logement.dart';
import '../../services/credit_service.dart';
import '../../services/depense_service.dart';
import '../../services/etat_des_lieux_service.dart';
import '../../services/fiscalite_service.dart';
import '../../services/locataire_service.dart';
import '../../services/logement_service.dart';
import '../../services/contrat_bail_service.dart';
import '../../services/diagnostic_service.dart';
import '../../services/quittance_service.dart';
import '../../services/sci_service.dart';
import '../../services/user_service.dart';
import '../../services/compta_export_service.dart';
import '../../services/rappel_service.dart';
import '../backup/backup_screen.dart';
import '../contrats/mes_contrats_screen.dart';
import '../diagnostics/mes_diagnostics_screen.dart';
import '../documents/documents_screen.dart';
import '../etat_des_lieux/etat_des_lieux_list_screen.dart';
import '../finance/finance_dashboard_screen.dart';
import '../locataires/mes_locataires_screen.dart';
import '../logements/logement_form_screen.dart';
import '../rappels/rappels_screen.dart';
import '../logements/logement_list_screen.dart';
import '../quittances/quittance_form_screen.dart';
import '../quittances/quittance_list_screen.dart';
import '../share/share_with_tenant_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<UserService>().current;
    if (profile == null) return const SizedBox.shrink();

    final logements = context.watch<LogementService>().all;
    final locataires = context.watch<LocataireService>().all;
    final quittances = context.watch<QuittanceService>().all;
    final edls = context.watch<EtatDesLieuxService>().all;
    final contrats = context.watch<ContratBailService>().all;
    final creditsSvc = context.watch<CreditService>();
    final depensesSvc = context.watch<DepenseService>();
    final fiscaliteSvc = context.watch<FiscaliteService>();
    final sciSvc = context.watch<SCIService>();

    final now = DateTime.now();
    final monthName = DateFormat('MMMM', 'fr_FR').format(now);

    final occupiedLogementIds = <String>{
      for (final l in locataires) ...l.logementIds,
    };
    final occupiedCount = logements.where((l) => occupiedLogementIds.contains(l.id)).length;
    // Loyers groupés par devise (jamais de somme EUR + CHF).
    final loyersParDevise = <String, double>{};
    for (final l in logements.where((l) => occupiedLogementIds.contains(l.id))) {
      loyersParDevise[l.currencyCode] =
          (loyersParDevise[l.currencyCode] ?? 0) + l.loyerTTC;
    }
    final occupationPct = logements.isEmpty
        ? 0
        : ((occupiedCount / logements.length) * 100).round();

    // Bilan net annuel — aligné sur le tableau de bord Finance pour éviter
    // toute divergence d'affichage. Mêmes règles :
    //  - recettes réellement encaissées (loyer payé dédoublonné par
    //    colocataires + régularisations/avances) via la source unique
    //    QuittanceService.encaisseParMoisLogement
    //  - dépenses cumulées de l'année
    //  - crédits via annualPaymentsForLogement (rachat + mois actifs)
    //  - impôts fonciers N-1 (surplus IR + PS) + coût fiscal IS des SCI
    final year = now.year;
    // Recettes et sorties groupées par devise du bien.
    final revenuParDevise = <String, double>{};
    final sortiesParDevise = <String, double>{};
    for (final l in logements) {
      final cur = l.currencyCode;
      final encaisse = QuittanceService.encaisseParMoisLogement(
        quittances: quittances,
        logementId: l.id,
        year: year,
      );
      for (final v in encaisse.values) {
        revenuParDevise[cur] = (revenuParDevise[cur] ?? 0) + v;
      }
      sortiesParDevise[cur] = (sortiesParDevise[cur] ?? 0) +
          depensesSvc.totalForLogementYear(l.id, year) +
          creditsSvc.annualPaymentsForLogement(l.id, year);
    }
    // Impôts français (foyer, EUR) : imputés à la devise EUR uniquement.
    double impotFoncier = 0.0;
    if (BaremeIR2026.aBaremePour(year - 1)) {
      final c = fiscaliteSvc.calculer(year - 1);
      impotFoncier = c.impotAdditionnelFoncierNet + c.prelevementsSociaux;
    }
    final impotSCI = sciSvc.totalCoutFiscalIS(year);
    if (impotFoncier != 0 || impotSCI != 0) {
      sortiesParDevise['EUR'] =
          (sortiesParDevise['EUR'] ?? 0) + impotFoncier + impotSCI;
    }
    final bilanParDevise = <String, double>{};
    for (final cur in {...revenuParDevise.keys, ...sortiesParDevise.keys}) {
      bilanParDevise[cur] =
          (revenuParDevise[cur] ?? 0) - (sortiesParDevise[cur] ?? 0);
    }

    // Première quittance à générer ce mois
    _PendingQuittance? alert;
    for (final l in logements) {
      final ls = locataires
          .where((x) => x.logementIds.contains(l.id))
          .toList();
      for (final loc in ls) {
        final exists = quittances.any((q) =>
            q.locataireId == loc.id &&
            q.logementId == l.id &&
            q.periodYear == now.year &&
            q.periodMonth == now.month);
        if (!exists) {
          alert = _PendingQuittance(logement: l, locataire: loc);
          break;
        }
      }
      if (alert != null) break;
    }

    final villes = logements
        .map((l) => l.ville.trim())
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final villeLabel = villes.isEmpty
        ? 'Aucune ville renseignée'
        : (villes.length <= 2 ? villes.join(', ') : '${villes.take(2).join(', ')}…');

    final allUpToDate = locataires.isNotEmpty &&
        locataires.every((loc) => loc.logementIds.every((lid) => quittances.any((q) =>
            q.locataireId == loc.id &&
            q.logementId == lid &&
            q.periodYear == now.year &&
            q.periodMonth == now.month)));

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _Hero(profile: profile),
          Transform.translate(
            offset: const Offset(0, -28),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _KpiStrip(
                loyers: CurrencyFormat.formatByCurrency(loyersParDevise),
                biens: '${logements.length}',
                occupation: '$occupationPct',
              ),
            ),
          ),
          const ForeignBackupBanner(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            child: Column(
              children: [
                if (alert != null) ...[
                  _AlertBanner(
                    title: 'Quittance de $monthName à générer',
                    subtitle:
                        '${alert.locataire.fullName} · ${alert.logement.libelle} · ${CurrencyFormat.format(alert.logement.loyerTTC, alert.logement.currencyCode)}',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const QuittanceFormScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                _QuickActions(
                  onQuittance: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const QuittanceFormScreen(),
                    ),
                  ),
                  onAddBien: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const LogementFormScreen(),
                    ),
                  ),
                  onEdl: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const EtatDesLieuxListScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                _SectionLabel('GESTION LOCATIVE'),
                _SectionGroup(
                  items: [
                    _SectionItem(
                      icon: Icons.home_outlined,
                      iconColor: AppColors.primary,
                      iconBg: AppColors.primary.withValues(alpha: 0.10),
                      title: 'Mes logements',
                      subtitle:
                          '${logements.length} bien${logements.length > 1 ? 's' : ''} · $villeLabel',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const LogementListScreen(),
                        ),
                      ),
                    ),
                    _SectionItem(
                      icon: Icons.people_alt_outlined,
                      iconColor: const Color(0xFF8B5CF6),
                      iconBg: const Color(0xFF8B5CF6).withValues(alpha: 0.10),
                      title: 'Mes locataires',
                      subtitle:
                          '${locataires.length} actif${locataires.length > 1 ? 's' : ''}'
                          '${allUpToDate ? ' · Tous à jour' : ''}',
                      trailing: allUpToDate
                          ? const _StatusPill(
                              label: 'À jour', color: AppColors.success)
                          : null,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const MesLocatairesScreen(),
                        ),
                      ),
                    ),
                    _SectionItem(
                      icon: Icons.assignment_outlined,
                      iconColor: AppColors.accent,
                      iconBg: AppColors.accent.withValues(alpha: 0.12),
                      title: 'États des lieux',
                      subtitle:
                          '${edls.length} document${edls.length > 1 ? 's' : ''} archivé${edls.length > 1 ? 's' : ''}',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const EtatDesLieuxListScreen(),
                        ),
                      ),
                    ),
                    _SectionItem(
                      icon: Icons.description_outlined,
                      iconColor: const Color(0xFF0EA5E9),
                      iconBg: const Color(0xFF0EA5E9).withValues(alpha: 0.10),
                      title: 'Contrats de bail',
                      subtitle: contrats.isEmpty
                          ? 'Aucun bail · conforme loi ALUR'
                          : '${contrats.length} bail${contrats.length > 1 ? 's' : ''} · conformes loi ALUR',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const MesContratsScreen(),
                        ),
                      ),
                    ),
                    _DiagnosticsSectionItem(),
                    _RappelsSectionItem(),
                  ],
                ),
                const SizedBox(height: 24),
                _SectionLabel('FINANCES'),
                _SectionGroup(
                  items: [
                    _SectionItem(
                      icon: Icons.receipt_long_outlined,
                      iconColor: AppColors.success,
                      iconBg: AppColors.success.withValues(alpha: 0.10),
                      title: 'Quittances de loyer',
                      subtitle: 'Conformes loi ALUR',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const QuittanceListScreen(),
                        ),
                      ),
                    ),
                    _SectionItem(
                      icon: Icons.show_chart_rounded,
                      iconColor: AppColors.error,
                      iconBg: AppColors.error.withValues(alpha: 0.10),
                      title: 'Tableau de bord',
                      subtitle:
                          'Bilan net : ${CurrencyFormat.formatByCurrency(bilanParDevise, signed: true, separator: ' · ')}',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const FinanceDashboardScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _SectionLabel('OUTILS'),
                _SectionGroup(
                  items: [
                    _SectionItem(
                      icon: Icons.folder_outlined,
                      iconColor: context.textSecondaryColor,
                      iconBg: context.textSecondaryColor.withValues(alpha: 0.10),
                      title: 'Mes documents',
                      subtitle: 'PDF, contrats, photos',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const DocumentsScreen(),
                        ),
                      ),
                    ),
                    _SectionItem(
                      icon: Icons.bluetooth_searching,
                      iconColor: AppColors.primary,
                      iconBg: AppColors.primary.withValues(alpha: 0.10),
                      title: 'Partager avec un locataire',
                      subtitle: 'Bluetooth · AirDrop · Nearby',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ShareWithTenantScreen(),
                        ),
                      ),
                    ),
                    _SectionItem(
                      icon: Icons.table_view_outlined,
                      iconColor: const Color(0xFF0EA5E9),
                      iconBg: const Color(0xFF0EA5E9).withValues(alpha: 0.10),
                      title: 'Export comptabilité (CSV)',
                      subtitle: 'Année courante : recettes + dépenses + crédits',
                      onTap: () => _exportCompta(context),
                    ),
                    _SectionItem(
                      icon: Icons.shield_outlined,
                      iconColor: AppColors.success,
                      iconBg: AppColors.success.withValues(alpha: 0.10),
                      title: 'Sauvegarde & restauration',
                      subtitle: 'Export chiffré de toutes vos données',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const BackupScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 120),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingQuittance {
  final Logement logement;
  final Locataire locataire;
  _PendingQuittance({required this.logement, required this.locataire});
}

class _Hero extends StatelessWidget {
  final dynamic profile;
  const _Hero({required this.profile});

  @override
  Widget build(BuildContext context) {
    final initials = (profile.firstName.isNotEmpty
            ? profile.firstName[0]
            : '') +
        (profile.lastName.isNotEmpty ? profile.lastName[0] : '');
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F1B3A),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.paddingOf(context).top + 14,
        20,
        56,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.key_rounded,
                  color: AppColors.accent, size: 18),
              const SizedBox(width: 6),
              const Text(
                'PROPRIÉTAIRE',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                ),
              ),
              const Spacer(),
              const BackupStatusBadge(),
              const SizedBox(width: 8),
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: const [
                    Icon(Icons.notifications_none_rounded,
                        color: Colors.white, size: 22),
                    Positioned(
                      top: 8,
                      right: 9,
                      child: CircleAvatar(
                        radius: 4,
                        backgroundColor: AppColors.accent,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              CircleAvatar(
                radius: 19,
                backgroundColor: AppColors.accent,
                child: Text(
                  initials.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'Bonjour ${profile.firstName}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w700,
              fontFamily: 'serif',
              height: 1.1,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Voici votre patrimoine ce mois-ci',
            style: TextStyle(color: Colors.white60, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _KpiStrip extends StatelessWidget {
  final String loyers;
  final String biens;
  final String occupation;
  const _KpiStrip({
    required this.loyers,
    required this.biens,
    required this.occupation,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black
                .withValues(alpha: context.isDark ? 0.4 : 0.08),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(child: _Kpi(label: 'LOYERS', value: loyers)),
          _KpiDivider(),
          Expanded(child: _Kpi(label: 'BIENS', value: biens)),
          _KpiDivider(),
          Expanded(
            child: _Kpi(
              label: 'OCCUPATION',
              value: occupation,
              suffix: '%',
              valueColor: AppColors.success,
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      width: 1,
      color: context.dividerColor,
    );
  }
}

class _Kpi extends StatelessWidget {
  final String label;
  final String value;
  final String? suffix;
  final Color? valueColor;
  const _Kpi({
    required this.label,
    required this.value,
    this.suffix,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: context.textSecondaryColor,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 6),
        RichText(
          text: TextSpan(
            text: value,
            style: TextStyle(
              color: valueColor ?? context.textPrimaryColor,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              fontFamily: 'serif',
            ),
            children: [
              if (suffix != null)
                TextSpan(
                  text: ' $suffix',
                  style: TextStyle(
                    color: valueColor ?? context.textSecondaryColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AlertBanner extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _AlertBanner({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final amber = const Color(0xFFFEF3C7);
    final amberDark = const Color(0xFFB45309);
    return HoverCard(
      onTap: onTap,
      accent: const Color(0xFFC66E1A),
      borderRadius: BorderRadius.circular(16),
      background: context.isDark ? const Color(0xFF3B2D08) : amber,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.access_time_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: amberDark,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: amberDark,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: amberDark),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  final VoidCallback onQuittance;
  final VoidCallback onAddBien;
  final VoidCallback onEdl;
  const _QuickActions({
    required this.onQuittance,
    required this.onAddBien,
    required this.onEdl,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _QuickAction(
            icon: Icons.receipt_long_outlined,
            label: 'Quittance',
            color: AppColors.success,
            onTap: onQuittance,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickAction(
            icon: Icons.home_outlined,
            label: 'Ajouter bien',
            color: AppColors.primary,
            onTap: onAddBien,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickAction(
            icon: Icons.assignment_outlined,
            label: 'État des lieux',
            color: const Color(0xFF8B5CF6),
            onTap: onEdl,
          ),
        ),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return HoverCard(
      onTap: onTap,
      accent: color,
      borderRadius: BorderRadius.circular(16),
      background: context.surfaceColor,
      borderColor: context.dividerColor,
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.textPrimaryColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 0, 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          style: TextStyle(
            color: context.textSecondaryColor,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}

class _SectionGroup extends StatelessWidget {
  final List<Widget> items;
  const _SectionGroup({required this.items});

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      children.add(items[i]);
      if (i < items.length - 1) {
        children.add(Divider(
          height: 1,
          thickness: 1,
          indent: 64,
          endIndent: 12,
          color: context.dividerColor,
        ));
      }
    }
    return Container(
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.dividerColor),
      ),
      child: Column(children: children),
    );
  }
}

class _SectionItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback onTap;

  const _SectionItem({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return HoverCard(
      onTap: onTap,
      accent: iconColor,
      borderRadius: BorderRadius.zero,
      background: Colors.transparent,
      borderColor: Colors.transparent,
      padding: const EdgeInsets.all(14),
      clip: false,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: context.textPrimaryColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.textSecondaryColor,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, color: context.textSecondaryColor),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _DiagnosticsSectionItem extends StatelessWidget {
  const _DiagnosticsSectionItem();

  @override
  Widget build(BuildContext context) {
    final diagnostics = context.watch<DiagnosticService>().all;
    final expires = diagnostics.where((d) => d.estExpire).length;
    return _SectionItem(
      icon: Icons.fact_check_outlined,
      iconColor: expires > 0 ? AppColors.error : AppColors.success,
      iconBg: (expires > 0 ? AppColors.error : AppColors.success)
          .withValues(alpha: 0.10),
      title: 'Diagnostics',
      subtitle: diagnostics.isEmpty
          ? 'DPE, ERP, plomb, gaz, électrique…'
          : '${diagnostics.length} diagnostic${diagnostics.length > 1 ? "s" : ""}'
              '${expires > 0 ? " · $expires à renouveler" : " · tous à jour"}',
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const MesDiagnosticsScreen(),
        ),
      ),
    );
  }
}

class _RappelsSectionItem extends StatelessWidget {
  const _RappelsSectionItem();

  @override
  Widget build(BuildContext context) {
    final rappels = context.watch<RappelService>().compute();
    final urgents = rappels.where((r) => r.severite >= 2).length;
    return _SectionItem(
      icon: Icons.notifications_active_outlined,
      iconColor: urgents > 0 ? AppColors.error : const Color(0xFF7C3AED),
      iconBg: (urgents > 0 ? AppColors.error : const Color(0xFF7C3AED))
          .withValues(alpha: 0.10),
      title: 'Rappels',
      subtitle: rappels.isEmpty
          ? 'Aucun rappel actif'
          : '${rappels.length} rappel${rappels.length > 1 ? "s" : ""}'
              '${urgents > 0 ? " · $urgents urgent${urgents > 1 ? "s" : ""}" : ""}',
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const RappelsScreen(),
        ),
      ),
    );
  }
}

Future<void> _exportCompta(BuildContext context) async {
  final year = DateTime.now().year;
  try {
    final svc = ComptaExportService();
    final path = await svc.exportYear(year);
    if (!context.mounted) return;
    await Share.shareXFiles(
      [XFile(path, mimeType: 'text/csv')],
      subject: 'Comptabilité ADDA Bailleur $year',
      text: 'Export CSV des recettes, dépenses et crédits de $year.',
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Échec de l\'export : $e')),
    );
  }
}
